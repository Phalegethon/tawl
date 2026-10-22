import Foundation

/// An immutable preview. This is deliberately neither Codable nor a queued command.
/// The executor must additionally revalidate the native identity and ownership.
public struct ProcessClosureIntent {
    public let processID: String
    public let pid: Int32
    public let startedAt: UInt64
    public let processName: String
    public let applicationID: String
    public let applicationName: String
    public let applicationMemberCount: Int
    public let reasons: [String]
    public let impact: [String]
    public let createdAt: Double
    fileprivate let recommendationKinds: [RecommendationKind]
}

public enum ProcessClosureBlock: Error, Equatable {
    case notLive, staleSample, identityChanged, applicationChanged, ownershipUnknown
    case protectedProcess, noRecommendation, recommendationChanged, expired, cancelled, notPending

    public var message: String {
        switch self {
        case .notLive: return L10n.text("Termination is available only in live monitoring.")
        case .staleSample: return L10n.text("The sample is stale; wait for a new live sample.")
        case .identityChanged: return L10n.text("The process exited or its identity changed; no request was sent.")
        case .applicationChanged: return L10n.text("The affected application changed; review it again.")
        case .ownershipUnknown: return L10n.text("An application process owned by this user could not be verified.")
        case .protectedProcess: return L10n.text("System, database, and virtual-machine processes cannot be terminated here.")
        case .noRecommendation: return L10n.text("No current termination recommendation exists for this process.")
        case .recommendationChanged: return L10n.text("The recommendation evidence changed; review the current state again.")
        case .expired: return L10n.text("The confirmation screen expired; select the process again.")
        case .cancelled: return L10n.text("Termination cancelled; no request was sent.")
        case .notPending: return L10n.text("This confirmation was already processed; no duplicate request was sent.")
        }
    }
}

private func closureSampleBlock(_ snapshot: Snapshot, now: Double, isLive: Bool) -> ProcessClosureBlock? {
    guard isLive else { return .notLive }
    guard now.isFinite, snapshot.monotonicTime.isFinite,
          now >= snapshot.monotonicTime, now - snapshot.monotonicTime <= 5 else { return .staleSample }
    return nil
}

private func closureStartedAt(_ process: ProcessSample) -> UInt64? {
    let parts = process.id.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, Int32(parts[0]) == process.pid,
          let started = UInt64(parts[1]), started > 0 else { return nil }
    return started
}

private func closureEligibilityBlock(_ process: ProcessSample) -> ProcessClosureBlock? {
    guard process.pid > 1 else { return .protectedProcess }
    guard closureStartedAt(process) != nil else { return .identityChanged }
    var executableIdentity = process
    executableIdentity.applicationID = "process:" + process.id
    executableIdentity.applicationName = process.name
    let protectedCategories: Set<UsageCategory> = [.system, .databases, .virtualization]
    if protectedCategories.contains(usageCategory(for: process)) ||
        protectedCategories.contains(usageCategory(for: executableIdentity)) { return .protectedProcess }
    guard process.canReviewClosure == true,
          process.applicationID.hasPrefix("app:"), !process.applicationName.isEmpty else { return .ownershipUnknown }
    return nil
}

public func prepareProcessClosure(process: ProcessSample, snapshot: Snapshot, assessment: ProcessAssessment,
                                  now: Double, isLive: Bool) -> Result<ProcessClosureIntent, ProcessClosureBlock> {
    if let block = closureSampleBlock(snapshot, now: now, isLive: isLive) { return .failure(block) }
    guard let current = snapshot.processes.first(where: { $0.id == process.id }), current.pid == process.pid else {
        return .failure(.identityChanged)
    }
    guard current.applicationID == process.applicationID, current.applicationName == process.applicationName else {
        return .failure(.applicationChanged)
    }
    if let block = closureEligibilityBlock(current) { return .failure(block) }
    let memberCount = Set(snapshot.processes.filter { $0.applicationID == current.applicationID }.map(\.id)).count
    return .success(ProcessClosureIntent(
        processID: current.id, pid: current.pid, startedAt: closureStartedAt(current)!,
        processName: cleanText(current.name), applicationID: current.applicationID,
        applicationName: cleanText(current.applicationName), applicationMemberCount: memberCount,
        reasons: assessment.recommendations.isEmpty
            ? [L10n.text("Manual selection · no automatic termination recommendation.")]
            : assessment.recommendations.map { cleanText($0.title) },
        impact: [L10n.text("A termination request will be sent only to the selected process (PID \(current.pid))."),
                 L10n.text("A tab, window, or background task in \(cleanText(current.applicationName)) may be interrupted; the entire application may also be affected."),
                 L10n.text("Unsaved changes may be lost. No direct request is sent to other processes; the application may restart this process.")],
        createdAt: now, recommendationKinds: assessment.recommendations.map(\.kind)))
}

public func validateProcessClosure(_ intent: ProcessClosureIntent, snapshot: Snapshot, assessment: ProcessAssessment,
                                   now: Double, isLive: Bool) -> ProcessClosureBlock? {
    if let block = closureSampleBlock(snapshot, now: now, isLive: isLive) { return block }
    guard now >= intent.createdAt, now - intent.createdAt <= 30 else { return .expired }
    guard let current = snapshot.processes.first(where: { $0.id == intent.processID }),
          current.pid == intent.pid, closureStartedAt(current) == intent.startedAt else { return .identityChanged }
    guard current.applicationID == intent.applicationID,
          cleanText(current.applicationName) == intent.applicationName else { return .applicationChanged }
    if let block = closureEligibilityBlock(current) { return block }
    // Advice describes resource observations, not permission. A user may choose
    // any eligible app process, even when a recommendation changes during review.
    return nil
}

public enum ProcessClosureChoice { case cancel, confirm }
public enum ProcessClosureSubmission { case sent, rejected(String) }
/// Result of checking the original PID and generation directly with the OS.
public enum ProcessClosureObservation { case alive, exited, replaced, unreadable }
public enum ProcessClosureStatus: Equatable {
    case preview, cancelled, submitting, waitingForExit, exitObserved, identityChanged, stillRunning, unverified, rejected(String)
}

/// One confirmation can produce at most one executor call. Signal acceptance is
/// deliberately separate from observing the original process lifetime disappear.
public struct ProcessClosureSession {
    public let intent: ProcessClosureIntent
    public private(set) var choice: ProcessClosureChoice = .cancel
    public private(set) var status: ProcessClosureStatus = .preview
    private var submittedAt: Double?

    public init(intent: ProcessClosureIntent) { self.intent = intent }
    public mutating func choose(_ choice: ProcessClosureChoice) {
        guard status == .preview else { return }; self.choice = choice
    }
    public mutating func cancel() {
        guard status == .preview else { return }; status = .cancelled
    }
    public mutating func consumeConfirmation(snapshot: Snapshot, assessment: ProcessAssessment, now: Double,
                                             isLive: Bool) -> Result<ProcessClosureIntent, ProcessClosureBlock> {
        guard status == .preview else { return .failure(.notPending) }
        guard choice == .confirm else { status = .cancelled; return .failure(.cancelled) }
        if let block = validateProcessClosure(intent, snapshot: snapshot, assessment: assessment, now: now, isLive: isLive) {
            status = .rejected(block.message); return .failure(block)
        }
        status = .submitting
        return .success(intent)
    }
    public mutating func markSubmission(_ result: ProcessClosureSubmission, now: Double) {
        guard status == .submitting else { return }
        switch result {
        case .sent:
            submittedAt = now; status = .waitingForExit
        case .rejected(let reason): status = .rejected(cleanText(reason))
        }
    }
    /// Replacing the native ticket ends this observation without implying exit.
    public mutating func invalidateObservation() {
        if [.waitingForExit, .stillRunning, .unverified].contains(status) { status = .unverified }
    }
    public mutating func observeNative(_ observation: ProcessClosureObservation, now: Double) {
        guard [.waitingForExit, .stillRunning, .unverified].contains(status), let submittedAt,
              now.isFinite, now >= submittedAt else { return }
        let timedOut = now - submittedAt >= 10
        switch observation {
        case .exited: status = .exitObserved
        case .replaced: status = .identityChanged
        case .alive: status = timedOut ? .stillRunning : .waitingForExit
        case .unreadable:
            if timedOut { status = .unverified }
        }
    }
    public mutating func observe(snapshot: Snapshot, now: Double) {
        guard [.waitingForExit, .stillRunning, .unverified].contains(status), let submittedAt,
              now.isFinite, now >= submittedAt else { return }
        let timedOut = now - submittedAt >= 10
        guard snapshot.monotonicTime.isFinite, snapshot.monotonicTime > submittedAt,
              now >= snapshot.monotonicTime, now - snapshot.monotonicTime <= 5 else {
            if timedOut { status = .unverified }; return
        }
        if snapshot.processes.contains(where: { $0.id == intent.processID }) {
            status = timedOut ? .stillRunning : .waitingForExit
        } else if snapshot.processes.contains(where: { $0.pid == intent.pid && $0.id != intent.processID }) {
            status = .identityChanged
        } else if timedOut {
            // Zero unreadable identities does not establish a complete process
            // enumeration: collection can fail or truncate before that count exists.
            // Only a direct native check may establish that the target exited.
            status = .unverified
        }
    }
}
