import XCTest
@testable import TawlCore

final class ClosureImpactUITests: XCTestCase {
    func sample(_ t: Double, after: Bool = false, missing: Bool = false) -> Snapshot {
        var s = TerminalClosureTests().snapshot(t)
        s.timestamp = Date(timeIntervalSince1970: 1_790_000_000+t)
        s.intervalSeconds = 2; s.cpuPercent = missing ? nil:(after ? 25:75)
        s.pressure = missing ? .unknown:(after ? .normal:.warning)
        s.swapUsedBytes = missing ? nil:(after ? 19_000_000_000:20_000_000_000)
        s.swapOutBytesPerSecond = missing ? nil:(after ? 0:2_000_000)
        return s
    }
    func submitted() -> (TerminalState, ClosureControllerSpy) {
        var state = TerminalState()
        for t in stride(from: 70.0, through: 100, by: 2) { state.accept(sample(t)) }
        state.openDetails(); let controller = ClosureControllerSpy()
        state.beginClosure(using: controller, now: 100); state.chooseClosure(.confirm)
        state.confirmClosure(using: controller, now: 100)
        return (state,controller)
    }
    func testAcceptedRequestOpensComparisonAndHidingPreservesCollection() {
        var (s,controller) = submitted()
        XCTAssertTrue(s.impactVisible); XCTAssertEqual(s.closureImpact?.startedAt,100)
        s.dismissClosure(using: controller)
        XCTAssertFalse(s.impactVisible); XCTAssertNotNil(s.closureImpact)
        let next = sample(102,after:true); s.accept(next); s.captureImpact(next,now:102)
        controller.observation = .exited; s.observeClosure(using:controller,now:102)
        XCTAssertEqual(s.impactSession?.status,.exitObserved)
        s.openImpact()
        XCTAssertTrue(s.impactVisible); XCTAssertEqual(s.closureImpact?.after.count,1)
    }
    func testCancellationDoesNotReplaceOldComparisonAndPreparationInvalidatesOnlyPendingOutcome() {
        var (s,controller) = submitted(); s.dismissClosure(using:controller)
        s.accept(sample(102)); s.beginClosure(using:controller,now:102)
        XCTAssertEqual(s.impactSession?.status,.unverified)
        s.dismissClosure(using:controller)
        XCTAssertEqual(s.closureImpact?.startedAt,100)
        s.openImpact(); XCTAssertTrue(s.impactVisible)
        XCTAssertEqual(controller.submitted.count,1)
    }
    func testCompletionFreezesDataWhileHiddenAndReopenDoesNotResetTime() {
        var (s,controller) = submitted(); s.dismissClosure(using:controller)
        for t in stride(from:102.0,through:160,by:2) { s.captureImpact(sample(t,after:true),now:t) }
        XCTAssertTrue(s.closureImpact!.isComplete)
        let after = s.closureImpact!.after.count
        s.captureImpact(sample(162),now:162); s.openImpact()
        XCTAssertEqual(s.closureImpact!.after.count,after); XCTAssertEqual(s.closureImpact!.elapsed,60)
        XCTAssertEqual(s.closureImpact!.startedAt,100)
    }
    func testAllMetricsAndBoundaryVisibleInSmallAndLargeViewports() {
        var (s,controller) = submitted()
        for t in stride(from:102.0,through:130,by:2) { s.captureImpact(sample(t,after:true),now:t) }
        controller.observation = .exited; s.observeClosure(using:controller,now:130)
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] {
            let f = TerminalRenderer.render(s,width:w,height:h), text=f.lines.joined(separator:"\n")
            for label in ["SYSTEM CPU","MEMORY PRESSURE","SWAP STOCK","SWAP WRITES","REQUEST","30 / 60 s","25.0%","−50.0 points"] {
                XCTAssertTrue(text.contains(label),"\(w)x\(h) missing \(label)")
            }
            XCTAssertTrue(text.contains("EXIT VERIFIED"))
            XCTAssertTrue(text.contains("does not prove causation"))
            XCTAssertTrue(f.lines.allSatisfy{TerminalText.width($0)<=w})
            XCTAssertEqual(f.lines.count,h)
        }
    }
    func testMissingMetricsAndNoReportAreExplicit() {
        var empty = TerminalState(); empty.openImpact()
        XCTAssertFalse(empty.impactVisible); XCTAssertFalse(empty.notice.isEmpty)
        var (s,_) = submitted(); s.captureImpact(sample(102,after:true,missing:true),now:102)
        let text = TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("Unknown")); XCTAssertTrue(text.contains("—"))
        XCTAssertFalse(text.contains("0.0%"))
    }
    func testChartsDistinguishGapsFutureAndMeasuredZero() {
        var (s,_) = submitted()
        s.captureImpact(sample(102,after:true),now:102)
        let cells=TerminalRenderer.impactCells(s.closureImpact!,width:90,metric:.writes)
        if case .value(let rate)=cells[30] { XCTAssertEqual(rate,0) } else { XCTFail("measured zero disappeared") }
        if case .future=cells[32] {} else { XCTFail("future fabricated") }
        s.captureImpact(sample(104,after:true,missing:true),now:104)
        let gaps=TerminalRenderer.impactCells(s.closureImpact!,width:90,metric:.writes)
        if case .missing=gaps[32] {} else { XCTFail("gap bridged") }
    }
    func testLongApplicationCannotHideTargetOrRequestTime() {
        var s=TerminalState(); var long=sample(100)
        for i in long.processes.indices {long.processes[i].applicationName=String(repeating:"Very long application name ",count:20)}
        s.accept(long); s.openDetails(); let controller=ClosureControllerSpy()
        s.beginClosure(using:controller,now:100); s.chooseClosure(.confirm)
        s.confirmClosure(using:controller,now:100)
        let text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("PID 42")); XCTAssertTrue(text.contains("Request \(TerminalRenderer.time(s.closureImpact!.startedOn))"))
        XCTAssertTrue(text.contains("Very long application"))
    }
    func testFrozenReportDoesNotClaimCurrentProcessState() {
        var (s,controller)=submitted()
        s.observeClosure(using:controller,now:112); s.advanceImpact(now:160)
        s.dismissClosure(using:controller); s.advanceImpact(now:300); s.openImpact()
        let text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("RUNNING AT LAST CHECK"))
        XCTAssertFalse(text.contains("STILL RUNNING"))
        var (unobserved,_)=submitted(); unobserved.advanceImpact(now:160)
        let unknown=TerminalRenderer.render(unobserved,width:80,height:24).lines.joined()
        XCTAssertTrue(unknown.contains("EXIT NOT OBSERVED")); XCTAssertFalse(unknown.contains("WAITING"))
    }
    func testImpactCaptureWhenRequested() throws {
        guard let dir=ProcessInfo.processInfo.environment["TAWL_IMPACT_CAPTURE"] else { return }
        try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
        func save(_ s:TerminalState,_ w:Int,_ h:Int,_ name:String) throws {
            let f=TerminalRenderer.render(s,width:w,height:h)
            try f.coloredLines.joined(separator:"\n").write(toFile:"\(dir)/\(name).ansi",atomically:true,encoding:.utf8)
        }
        var (s,controller)=submitted()
        try save(s,80,24,"impact-initial-80x24")
        for t in stride(from:102.0,through:130,by:2) { s.captureImpact(sample(t,after:true),now:t) }
        controller.observation = .exited; s.observeClosure(using:controller,now:130)
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] { try save(s,w,h,"impact-\(w)x\(h)") }
        for t in stride(from:132.0,through:160,by:2) { s.captureImpact(sample(t,after:true),now:t) }
        try save(s,143,45,"impact-complete-143x45")
        var (missing,_) = submitted(); missing.captureImpact(sample(102,after:true,missing:true),now:102)
        missing.advanceImpact(now:112)
        try save(missing,80,24,"impact-missing-80x24")
        var partial=TerminalState(); partial.accept(sample(98)); partial.accept(sample(100)); partial.openDetails()
        let partialController=ClosureControllerSpy()
        partial.beginClosure(using:partialController,now:100); partial.chooseClosure(.confirm)
        partial.confirmClosure(using:partialController,now:100)
        partial.captureImpact(sample(102,after:true),now:102)
        try save(partial,80,24,"impact-partial-baseline-80x24")
        var flat=TerminalState()
        for t in stride(from:70.0,through:100,by:2) {
            var point=sample(t); point.cpuPercent=65+15*sin(t/4); flat.accept(point)
        }
        flat.openDetails(); let flatController=ClosureControllerSpy()
        flat.beginClosure(using:flatController,now:100); flat.chooseClosure(.confirm)
        flat.confirmClosure(using:flatController,now:100)
        for t in stride(from:102.0,through:160,by:2) {
            var point=sample(t,after:true); point.swapUsedBytes=20_000_000_000
            point.cpuPercent=22+8*sin(t/3); flat.captureImpact(point,now:t)
        }
        flatController.observation = .exited; flat.observeClosure(using:flatController,now:160)
        try save(flat,143,45,"impact-stock-flat-143x45")
        var long=TerminalState(); var point=sample(100)
        for i in point.processes.indices {point.processes[i].applicationName=String(repeating:"Very long application name ",count:20)}
        long.accept(point); long.openDetails(); let longController=ClosureControllerSpy()
        long.beginClosure(using:longController,now:100); long.chooseClosure(.confirm)
        long.confirmClosure(using:longController,now:100); long.advanceImpact(now:112)
        long.observeClosure(using:longController,now:112)
        try save(long,160,45,"impact-long-running-160x45")
        var completedRunning=long; completedRunning.advanceImpact(now:160)
        try save(completedRunning,80,24,"impact-complete-running-80x24")
        longController.observation = .replaced; long.observeClosure(using:longController,now:114)
        try save(long,80,24,"impact-identity-changed-80x24")
    }
}
