import XCTest
@testable import TawlCore

final class ProcessClosureTests: XCTestCase {
    func process() -> ProcessSample {
        var p = ProcessSample(id: "42:100", pid: 42, name: "Browser Helper", applicationID: "app:browser",
                              applicationName: "Browser", cpuCores: 0.1, footprintBytes: 3_221_225_472)
        p.canReviewClosure = true
        return p
    }
    func snapshot(_ p: ProcessSample? = nil, time: Double = 100) -> Snapshot {
        var s = Snapshot(monotonicTime: time)
        s.pressure = .warning; s.processes = [p ?? process()]; s.totalProcessCount = 1
        return s
    }
    func assessment(_ s: Snapshot) -> ProcessAssessment {
        assessProcess(s.processes[0], snapshot: s, history: [s])
    }
    func prepare(_ s: Snapshot? = nil, now: Double = 101, live: Bool = true) -> Result<ProcessClosureIntent, ProcessClosureBlock> {
        let s = s ?? snapshot()
        return prepareProcessClosure(process: s.processes[0], snapshot: s, assessment: assessment(s), now: now, isLive: live)
    }
    func testPreviewNamesAffectedApplicationAndLimitsScopeToSelectedProcess() throws {
        var s = snapshot(); var sibling = process(); sibling.id = "43:101"; sibling.pid = 43
        s.processes.append(sibling)
        let intent = try prepare(s).get()
        XCTAssertEqual(intent.processID, "42:100")
        XCTAssertEqual(intent.applicationName, "Browser")
        XCTAssertEqual(intent.applicationMemberCount, 2)
        XCTAssertEqual(intent.startedAt, 100)
        XCTAssertTrue(intent.impact.joined().contains("only to the selected process"))
        XCTAssertFalse(intent.reasons.isEmpty)
    }
    func testPinnedStaleFutureAndInvalidClocksCannotPrepare() {
        XCTAssertEqual(prepare(live: false).failure, .notLive)
        XCTAssertEqual(prepare(now: 106).failure, .staleSample)
        XCTAssertEqual(prepare(now: 99).failure, .staleSample)
        XCTAssertEqual(prepare(now: .nan).failure, .staleSample)
        XCTAssertEqual(prepare(snapshot(time: .infinity)).failure, .staleSample)
    }
    func testUnownedUnknownAndProtectedProcessesCannotPrepare() {
        var p = process(); p.canReviewClosure = false
        XCTAssertEqual(prepare(snapshot(p)).failure, .ownershipUnknown)
        p.canReviewClosure = nil
        XCTAssertEqual(prepare(snapshot(p)).failure, .ownershipUnknown)
        p = process(); p.applicationName = "Docker"
        XCTAssertEqual(prepare(snapshot(p)).failure, .protectedProcess)
        p = process(); p.name = "postgres"
        XCTAssertEqual(prepare(snapshot(p)).failure, .protectedProcess)
        p = process(); p.pid = 1; p.id = "1:100"
        XCTAssertEqual(prepare(snapshot(p)).failure, .protectedProcess)
        p = process(); p.id = "42:invalid"
        XCTAssertEqual(prepare(snapshot(p)).failure, .identityChanged)
    }
    func testConfirmationRejectsReusedPIDChangedAppAndExpiredIntent() throws {
        let intent = try prepare().get()
        var p = process(); p.id = "42:101"
        var s = snapshot(p, time: 102)
        XCTAssertEqual(validateProcessClosure(intent, snapshot: s, assessment: assessment(s), now: 103, isLive: true), .identityChanged)
        p = process(); p.applicationID = "app:other"; s = snapshot(p, time: 102)
        XCTAssertEqual(validateProcessClosure(intent, snapshot: s, assessment: assessment(s), now: 103, isLive: true), .applicationChanged)
        s = snapshot(time: 132)
        XCTAssertEqual(validateProcessClosure(intent, snapshot: s, assessment: assessment(s), now: 133, isLive: true), .expired)
    }
    func testManualOwnedProcessCanBeReviewedWithoutRecommendation() throws {
        var p = process(); p.footprintBytes = 104_857_600; p.ageSeconds = 60
        var s = snapshot(p); s.pressure = .normal
        XCTAssertTrue(assessment(s).recommendations.isEmpty)
        let intent = try prepare(s).get()
        XCTAssertTrue(intent.reasons.joined().contains("Manual selection"))
        XCTAssertEqual(intent.pid, p.pid)
        XCTAssertEqual(intent.applicationName, p.applicationName)
        XCTAssertEqual(validateProcessClosure(intent, snapshot:s, assessment:assessment(s), now:102, isLive:true), nil)
    }
    func testChangingRecommendationsDoesNotRevokeExplicitManualChoiceButOwnershipStillDoes() throws {
        let intent = try prepare().get()
        var s = snapshot(time:102); s.pressure = .normal
        XCTAssertTrue(assessment(s).recommendations.isEmpty)
        XCTAssertNil(validateProcessClosure(intent,snapshot:s,assessment:assessment(s),now:103,isLive:true))
        s.processes[0].canReviewClosure = false
        XCTAssertEqual(validateProcessClosure(intent,snapshot:s,assessment:assessment(s),now:103,isLive:true),.ownershipUnknown)
    }
    func testDefaultCancelAndCancelledSessionsNeverYieldARequest() throws {
        var session = ProcessClosureSession(intent: try prepare().get())
        XCTAssertEqual(session.choice, .cancel)
        let s = snapshot(time: 102)
        XCTAssertEqual(session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 103, isLive: true).failure, .cancelled)
        XCTAssertEqual(session.status, .cancelled)
        session.choose(.confirm)
        XCTAssertEqual(session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 103, isLive: true).failure, .notPending)
    }
    func testExplicitConfirmationIsConsumedBeforeExecutorAndCannotBeReplayed() throws {
        var session = ProcessClosureSession(intent: try prepare().get())
        session.choose(.confirm)
        let s = snapshot(time: 102)
        let intent = try session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 103, isLive: true).get()
        XCTAssertEqual(intent.processID, "42:100")
        XCTAssertEqual(session.status, .submitting)
        XCTAssertEqual(session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 103, isLive: true).failure, .notPending)
        session.markSubmission(.sent, now: 103)
        XCTAssertEqual(session.status, .waitingForExit)
        session.observe(snapshot: snapshot(time: 104), now: 104)
        XCTAssertEqual(session.status, .waitingForExit)
        session.observe(snapshot: snapshot(time: 114), now: 114)
        XCTAssertEqual(session.status, .stillRunning)
    }
    func testSnapshotAbsenceCannotProveExitEvenWithZeroUnreadableCount() throws {
        var session = try submittedSession()
        var absent = snapshot(time: 104); absent.processes = []; absent.totalProcessCount = 0
        var old = absent; old.monotonicTime = 102
        session.observe(snapshot: old, now: 104)
        XCTAssertEqual(session.status, .waitingForExit)
        absent.unreadableProcessCount = 1; absent.monotonicTime = 114
        session.observe(snapshot: absent, now: 114)
        XCTAssertEqual(session.status, .unverified)
        absent.unreadableProcessCount = 0; absent.monotonicTime = 116
        session.observe(snapshot: absent, now: 116)
        XCTAssertEqual(session.status, .unverified)
        session.observeNative(.exited, now: 116)
        XCTAssertEqual(session.status, .exitObserved)
    }
    func testSnapshotChangedPIDIdentityDoesNotClaimExitOrReplacementClosure() throws {
        var session = try submittedSession()
        var p = process(); p.id = "42:999"
        var s = snapshot(p, time: 104); s.unreadableProcessCount = 10
        session.observe(snapshot: s, now: 104)
        XCTAssertEqual(session.status, .identityChanged)
    }
    func testNativeRejectionNeverBecomesSuccessfulSubmissionOrReplay() throws {
        var session = ProcessClosureSession(intent: try prepare().get()); session.choose(.confirm)
        let s = snapshot(time: 102)
        _ = try session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 103, isLive: true).get()
        session.markSubmission(.rejected("Identity changed"), now: 103)
        XCTAssertEqual(session.status, .rejected("Identity changed"))
        session.markSubmission(.sent, now: 104)
        XCTAssertEqual(session.status, .rejected("Identity changed"))
        var absent = snapshot(time: 106); absent.processes = []
        session.observe(snapshot: absent, now: 106)
        XCTAssertEqual(session.status, .rejected("Identity changed"))
    }
    func testNativeObservationIsIgnoredBeforeSubmissionAndAfterCancellation() throws {
        var session = ProcessClosureSession(intent: try prepare().get())
        session.observeNative(.exited, now: 104)
        XCTAssertEqual(session.status, .preview)
        session.cancel()
        session.observeNative(.alive, now: 114)
        session.observeNative(.exited, now: 114)
        XCTAssertEqual(session.status, .cancelled)
        session.choose(.confirm)
        let s = snapshot(time: 114)
        XCTAssertEqual(session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 114, isLive: true).failure, .notPending)
    }
    func testNativeObservationSeparatesAliveTimeoutAndUnverifiableFromExit() throws {
        var session = try submittedSession()
        session.observeNative(.alive, now: 104)
        XCTAssertEqual(session.status, .waitingForExit)
        session.observeNative(.unreadable, now: 105)
        XCTAssertEqual(session.status, .waitingForExit)
        session.observeNative(.alive, now: 114)
        XCTAssertEqual(session.status, .stillRunning)
        session.observeNative(.unreadable, now: 115)
        XCTAssertEqual(session.status, .unverified)
        session.observeNative(.exited, now: 116)
        XCTAssertEqual(session.status, .exitObserved)
        session.observeNative(.alive, now: 117)
        XCTAssertEqual(session.status, .exitObserved)
    }
    func testNativeObservationRejectsInvalidTimeAndRecognizesReplacedLifetime() throws {
        var session = try submittedSession()
        session.observeNative(.exited, now: .nan)
        session.observeNative(.exited, now: .infinity)
        session.observeNative(.exited, now: 102)
        XCTAssertEqual(session.status, .waitingForExit)
        session.observeNative(.replaced, now: 104)
        XCTAssertEqual(session.status, .identityChanged)
        session.observeNative(.exited, now: 105)
        XCTAssertEqual(session.status, .identityChanged)
    }
    func submittedSession() throws -> ProcessClosureSession {
        var session = ProcessClosureSession(intent: try prepare().get()); session.choose(.confirm)
        let s = snapshot(time: 102)
        _ = try session.consumeConfirmation(snapshot: s, assessment: assessment(s), now: 103, isLive: true).get()
        session.markSubmission(.sent, now: 103)
        return session
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let value) = self { return value }; return nil }
}
