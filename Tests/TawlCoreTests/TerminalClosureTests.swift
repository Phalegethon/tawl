import XCTest
@testable import TawlCore

final class ClosureControllerSpy: ProcessClosureControlling {
    var prepared: [String] = [], submitted: [String] = []
    var failure: String?, observation: ProcessClosureObservation = .alive
    func prepare(_ intent: ProcessClosureIntent) -> String? { prepared.append(intent.processID); return failure }
    func submit(_ intent: ProcessClosureIntent) -> ProcessClosureSubmission { submitted.append(intent.processID); return .sent }
    func observe(_ intent: ProcessClosureIntent) -> ProcessClosureObservation { observation }
    func clear() {}
}
final class TerminalClosureTests: XCTestCase {
    func snapshot(_ time: Double = 100) -> Snapshot {
        var s = ProcessClosureTests().snapshot(time: time)
        var sibling = s.processes[0]; sibling.pid = 43; sibling.id = "43:101"
        sibling.footprintBytes = 2_500_000_000; s.processes.append(sibling); s.totalProcessCount = 2
        return s
    }
    func state() -> TerminalState { var s = TerminalState(); s.accept(snapshot()); s.openDetails(); return s }
    func testCancelAndNativePreparationFailureNeverSignal() {
        var s = state(); let controller = ClosureControllerSpy()
        s.beginClosure(using: controller, now: 101)
        XCTAssertEqual(s.closureSession?.choice, .cancel)
        s.confirmClosure(using: controller, now: 101)
        XCTAssertTrue(controller.submitted.isEmpty)
        s.dismissClosure(using: controller)
        controller.failure = "macOS identity could not be verified"
        s.beginClosure(using: controller, now: 101)
        XCTAssertNil(s.closureSession); XCTAssertTrue(s.notice.contains("could not be verified"))
    }
    func testConfirmationTargetsPreviewEvenWhenSelectionChangesAndRunsOnce() {
        var s = state(); let controller = ClosureControllerSpy()
        s.beginClosure(using: controller, now: 101)
        let id = s.closureSession!.intent.processID
        s.moveProcess(by: 1)
        s.accept(snapshot(102)); s.chooseClosure(.confirm)
        s.confirmClosure(using: controller, now: 103)
        s.confirmClosure(using: controller, now: 103)
        XCTAssertEqual(controller.submitted, [id])
        XCTAssertEqual(s.closureSession?.status, .waitingForExit)
        controller.observation = .exited
        s.observeClosure(using: controller, now: 104)
        XCTAssertEqual(s.closureSession?.status, .exitObserved)
    }
    func testHistoryRejectsButAdviceChangesDoNotBlockExplicitConfirmation() {
        var s = state(); let controller = ClosureControllerSpy()
        s.toggleFrozen(); s.beginClosure(using: controller, now: 101)
        XCTAssertTrue(controller.prepared.isEmpty); XCTAssertNil(s.closureSession)
        s.toggleFrozen(); s.beginClosure(using: controller, now: 101)
        var next = snapshot(102); next.pressure = .normal; s.accept(next)
        s.chooseClosure(.confirm); s.confirmClosure(using: controller, now: 103)
        XCTAssertEqual(controller.submitted, ["42:100"])
        XCTAssertTrue(s.impactVisible)
    }
    func testConfirmationShowsAppScopeRiskAndDefaultCancelAtAllSizes() {
        var s = state(); let controller = ClosureControllerSpy(); s.beginClosure(using: controller, now: 101)
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] {
            let frame = TerminalRenderer.render(s, width: w, height: h)
            let text = frame.lines.joined(separator: "\n")
            XCTAssertTrue(text.contains("AFFECTED APPLICATION")); XCTAssertTrue(text.contains("Browser"))
            XCTAssertTrue(text.contains("PID 42")); XCTAssertTrue(text.contains("Unsaved"))
            XCTAssertTrue(text.contains("SIGTERM")); XCTAssertTrue(text.contains("› Cancel"))
            XCTAssertTrue(text.contains("Send termination request"))
            XCTAssertTrue(frame.lines.allSatisfy { TerminalText.width($0) <= w })
        }
    }
    func testFreshCollectorResultCannotFallBackToEarlierRetainedFrame() {
        var s = state(); let controller = ClosureControllerSpy()
        s.beginClosure(using: controller, now: 101); s.chooseClosure(.confirm)
        let stale = snapshot(90); s.accept(stale)
        XCTAssertEqual(s.visibleSnapshot?.monotonicTime, 100)
        s.confirmClosure(using: controller, now: 103, measuredSnapshot: stale)
        XCTAssertTrue(controller.submitted.isEmpty)
        XCTAssertEqual(s.closureSession?.status, .rejected(ProcessClosureBlock.staleSample.message))
    }
    func testLongImpactMustBeViewedBeforeConfirmation() {
        var long = snapshot()
        for i in long.processes.indices {
            long.processes[i].applicationName = String(repeating: "Long Application ", count: 24)
            long.processes[i].name = String(repeating: "Worker ", count: 12)
        }
        var s = TerminalState(); s.accept(long); s.openDetails()
        let controller = ClosureControllerSpy(); s.beginClosure(using: controller, now: 101)
        let frame = TerminalRenderer.render(s, width: 80, height: 24)
        XCTAssertGreaterThan(frame.maximumDetailScroll, 0)
        XCTAssertTrue(frame.lines.joined().contains("Read all impact information"))
        s.chooseClosure(.confirm)
        s.confirmClosure(using: controller, now: 101, maximumScroll: frame.maximumDetailScroll)
        XCTAssertTrue(controller.submitted.isEmpty)
        s.scrollClosure(by: 1000, limit: frame.maximumDetailScroll)
        s.confirmClosure(using: controller, now: 101, maximumScroll: frame.maximumDetailScroll)
        XCTAssertEqual(controller.submitted.count, 1)
    }
    func testResultRenderingDoesNotClaimExitForReplacedOrRunningIdentity() {
        var s = state(); let controller = ClosureControllerSpy()
        s.beginClosure(using: controller, now: 101); s.chooseClosure(.confirm)
        s.confirmClosure(using: controller, now: 101)
        controller.observation = .alive; s.observeClosure(using: controller, now: 112)
        var text = TerminalRenderer.render(s, width: 80, height: 24).lines.joined()
        XCTAssertTrue(text.contains("STILL RUNNING")); XCTAssertFalse(text.contains("EXIT VERIFIED"))
        controller.observation = .replaced; s.observeClosure(using: controller, now: 114)
        text = TerminalRenderer.render(s, width: 80, height: 24).lines.joined()
        XCTAssertTrue(text.contains("IDENTITY CHANGED")); XCTAssertFalse(text.contains("EXIT VERIFIED"))
    }
    func testCaptureClosurePreviewsWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["TAWL_CLOSURE_CAPTURE"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var s = state(); let controller = ClosureControllerSpy(); s.beginClosure(using: controller, now: 101)
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] {
            let frame = TerminalRenderer.render(s, width: w, height: h)
            try frame.coloredLines.joined(separator:"\n").write(toFile: "\(dir)/closure-\(w)x\(h).ansi", atomically: true, encoding: .utf8)
        }
        s.chooseClosure(.confirm); s.confirmClosure(using: controller, now: 101)
        let pending = TerminalRenderer.render(s, width: 100, height: 30)
        try pending.coloredLines.joined(separator:"\n").write(toFile: "\(dir)/closure-pending.ansi", atomically: true, encoding: .utf8)
        controller.observation = .exited; s.observeClosure(using: controller, now: 102)
        let result = TerminalRenderer.render(s, width: 100, height: 30)
        try result.coloredLines.joined(separator:"\n").write(toFile: "\(dir)/closure-result.ansi", atomically: true, encoding: .utf8)
    }
}
