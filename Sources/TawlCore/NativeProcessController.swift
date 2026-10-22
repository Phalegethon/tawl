import Foundation
import CTawl

public protocol ProcessClosureControlling: AnyObject {
    /// Read-only preparation. A message means no native ticket was retained.
    func prepare(_ intent: ProcessClosureIntent) -> String?
    func submit(_ intent: ProcessClosureIntent) -> ProcessClosureSubmission
    func observe(_ intent: ProcessClosureIntent) -> ProcessClosureObservation
    func clear()
}

/// The only adapter that sends a process signal. It operates on one short-lived
/// native audit token after a product-level confirmation has been consumed.
public final class NativeProcessController: ProcessClosureControlling {
    private var ticket: nb_process_control_ticket?
    private var boundIntent: ProcessClosureIntent?

    public init() {}

    public func prepare(_ intent: ProcessClosureIntent) -> String? {
        clear()
        var candidate = nb_process_control_ticket()
        let result = nb_process_control_prepare(intent.pid, intent.startedAt, &candidate)
        guard result == NB_CONTROL_OK else { return Self.message(for: result) }
        let path = Self.string(from: candidate.executable_path)
        guard !path.isEmpty else { return L10n.text("The application executable could not be verified.") }
        let raw = RawProcess(pid: candidate.pid, parentPID: candidate.parent_pid,
                             startedAt: candidate.start_microseconds,
                             name: Self.string(from: candidate.name), executablePath: path)
        let identity = Attributor().identify(raw, among: [])
        guard identity.applicationID == intent.applicationID,
              cleanText(identity.applicationName) == intent.applicationName else {
            return L10n.text("The live process belongs to a different application; termination preparation cancelled.")
        }
        ticket = candidate
        boundIntent = intent
        return nil
    }

    public func submit(_ intent: ProcessClosureIntent) -> ProcessClosureSubmission {
        guard matches(intent), var candidate = ticket else {
            return .rejected(L10n.text("No verified termination preparation exists for this process."))
        }
        let result = nb_process_control_terminate(&candidate)
        ticket = candidate
        return result == NB_CONTROL_OK ? .sent : .rejected(Self.message(for: result))
    }

    public func observe(_ intent: ProcessClosureIntent) -> ProcessClosureObservation {
        guard matches(intent), var candidate = ticket else { return .unreadable }
        switch Int(nb_process_control_status(&candidate)) {
        case NB_PROCESS_ALIVE: return .alive
        case NB_PROCESS_EXITED: return .exited
        case NB_PROCESS_REPLACED: return .replaced
        default: return .unreadable
        }
    }

    public func clear() { ticket = nil; boundIntent = nil }

    private func matches(_ intent: ProcessClosureIntent) -> Bool {
        guard let bound = boundIntent else { return false }
        return bound.processID == intent.processID && bound.pid == intent.pid &&
            bound.startedAt == intent.startedAt && bound.applicationID == intent.applicationID &&
            bound.applicationName == intent.applicationName && bound.createdAt == intent.createdAt
    }

    private static func string<T>(from value: T) -> String {
        withUnsafeBytes(of: value) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func message(for code: Int32) -> String {
        switch Int(code) {
        case NB_CONTROL_ANCESTRY_UNAVAILABLE:
            return L10n.text("The terminal ancestor chain could not be verified; termination preparation stopped. The target was not identified as protected.")
        case NB_CONTROL_PROTECTED:
            return L10n.text("This process is protected: system, infrastructure, another user, or an ancestor of this terminal session.")
        case NB_CONTROL_CHANGED:
            return L10n.text("The process exited or its identity changed; no termination request was sent.")
        case NB_CONTROL_EXPIRED:
            return L10n.text("The 30-second confirmation expired; select the process again.")
        case NB_CONTROL_ALREADY_USED:
            return L10n.text("This confirmation was already processed; no duplicate request was sent.")
        case NB_CONTROL_DENIED:
            return L10n.text("macOS denied the termination request.")
        case NB_CONTROL_UNAVAILABLE:
            return L10n.text("The live process identity could not be verified; no termination request was sent.")
        case NB_CONTROL_SIGNAL_FAILED:
            return L10n.text("macOS did not accept the termination request.")
        default:
            return L10n.text("Invalid termination request; select the process again.")
        }
    }
}
