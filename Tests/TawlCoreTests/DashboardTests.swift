import XCTest
@testable import TawlCore
final class DashboardTests: XCTestCase {
    func testUpdateNoticeUsesFooterWithoutDisplacingDataOrActionMessages() {
        for (w,h) in [(80,24),(100,30),(157,43)] {
            var state = populated()
            let before = TerminalRenderer.render(state,width:w,height:h)
            state.updateNotice = "TAWL 0.2.0 available · tawl update"
            let after = TerminalRenderer.render(state,width:w,height:h)
            XCTAssertTrue(after.lines[h-2].contains("tawl update"))
            XCTAssertEqual(after.visibleRowIDs,before.visibleRowIDs)
            XCTAssertEqual(Array(after.lines.prefix(h-2)),Array(before.lines.prefix(h-2)))
            XCTAssertTrue(after.lines.allSatisfy { TerminalText.width($0) <= w })
            state.notice = "Report saved"
            XCTAssertTrue(TerminalRenderer.render(state,width:w,height:h).lines[h-2].contains("Report saved"))
            state.searchEditing = true
            XCTAssertTrue(TerminalRenderer.render(state,width:w,height:h).lines[h-2].contains("SEARCH"))
        }
    }
    // Optional review artifacts from the exact renderer; never alters normal test runs.
    private func exportReviewFrames() throws {
        guard let directory=ProcessInfo.processInfo.environment["TAWL_CAPTURE_DIR"],
              let record=ProcessInfo.processInfo.environment["TAWL_CAPTURE_RECORD"] else {return}
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        var state=TerminalState()
        for snapshot in try RecordingReader.read(url:URL(fileURLWithPath:record)).snapshots {state.accept(snapshot)}
        state.toggleHistory()
        func save(_ state:TerminalState,_ w:Int,_ h:Int,_ name:String) throws {
            let frame=TerminalRenderer.render(state,width:w,height:h)
            try frame.coloredLines.joined(separator:"\n").write(toFile:directory+"/"+name+".ansi",atomically:true,encoding:.utf8)
            try frame.lines.joined(separator:"\n").write(toFile:directory+"/"+name+".txt",atomically:true,encoding:.utf8)
        }
        for (w,h) in [(80,24),(100,30),(140,72),(160,45)] {try save(state,w,h,"dashboard-\(w)x\(h)")}
        state.detailVisible=true;try save(state,100,30,"detail-100x30")
        state.detailVisible=false;state.setSearch("no_match_1234");try save(state,80,24,"empty-80x24")
        var missing=TerminalState();missing.accept(Snapshot(timestamp:Date(),monotonicTime:0))
        try save(missing,100,30,"missing-100x30")
    }
    func populated() -> TerminalState {
        var state = TerminalState()
        for t in stride(from: 0.0, through: 80, by: 2) {
            var s = Snapshot(timestamp: Date(timeIntervalSince1970: t), monotonicTime: t)
            s.cpuPercent = 35 + t/4; s.intervalSeconds = 2; s.logicalCPUCount = 12
            s.pressure = .warning; s.memoryTotalBytes = 32*1024*1024*1024
            s.swapUsedBytes = 20*1024*1024*1024; s.compressedBytes = 12*1024*1024*1024
            s.diskReadBytesPerSecond = t*1024*40; s.diskWriteBytesPerSecond = 1000
            s.networkInBytesPerSecond = 2000; s.networkOutBytesPerSecond = t*100
            s.processes = (0..<60).map { n -> ProcessSample in
                let cpu = Double(60-n) / 40.0
                let memory = UInt64(60-n) * 1_048_576
                return ProcessSample(id: "\(n):1", pid: Int32(n+1), name: "Worker", applicationID: "app\(n)", applicationName: "App \(n)", projectID: nil, projectName: nil, projectEvidence: nil, cpuCores: cpu, footprintBytes: memory, memoryDeltaBytes: 1024, diskReadBytesPerSecond: nil, diskWriteBytesPerSecond: nil)
            }
            s.totalProcessCount = 60; state.accept(s)
        }
        return state
    }
    func testWideScreenUsesContextInsteadOfAnEmptyNameColumn() {
        let f = TerminalRenderer.render(populated(),width:140,height:72)
        XCTAssertTrue(f.lines.joined().contains("SELECTED WORKLOAD"))
        let header = f.lines.first { $0.contains("2 CPU") && $0.contains("FOOTPRINT") }
        XCTAssertNotNil(header)
        XCTAssertLessThan(header?.distance(from:header!.startIndex,to:header!.range(of:"2 CPU")!.lowerBound) ?? 999,50)
        XCTAssertTrue(f.coloredLines.contains { $0.contains("48;5;") })
        XCTAssertTrue(f.lines.joined().contains("Scale"))
        XCTAssertTrue(f.lines.joined().contains("0–60.0 MiB · auto"),"Integer bytes must be converted numerically, not reinterpreted as floating-point bits")
    }
    func testGraphicsDoNotDisplaceComparisonRowsOrEscapeCellBounds() throws {
        for (w,h,count) in [(80,24,6),(100,30,10),(160,45,18)] {
            let f = TerminalRenderer.render(populated(),width:w,height:h)
            XCTAssertGreaterThanOrEqual(f.visibleRowIDs.count,count)
            XCTAssertTrue(f.lines.allSatisfy { TerminalText.width($0) <= w })
            XCTAssertTrue(f.lines.joined().contains("MEMORY"))
            XCTAssertTrue(f.lines.joined().contains("DISK") || f.lines.joined().contains("Disk"))
            XCTAssertEqual(f.coloredLines.count,h)
        }
        try exportReviewFrames()
    }
    func testFrozenResourceChartsDoNotIncludeLaterLiveSamples() {
        var state=populated();state.toggleFrozen()
        let before=TerminalRenderer.render(state,width:140,height:45)
        var next=Snapshot(timestamp:Date(timeIntervalSince1970:100),monotonicTime:100)
        next.cpuPercent=100;next.pressure = .critical;state.accept(next)
        let after=TerminalRenderer.render(state,width:140,height:45)
        XCTAssertEqual(Array(before.lines[3..<12]),Array(after.lines[3..<12]))
    }
    func testMissingScaleAndCapacityAreNotPresentedAsMeasurements() {
        var state=TerminalState();state.accept(Snapshot(timestamp:Date(),monotonicTime:0))
        let text=TerminalRenderer.render(state,width:100,height:30).lines.joined(separator:"\n")
        XCTAssertTrue(text.contains("Waiting for scale"))
        XCTAssertFalse(text.contains("0–1 B/s"))
        XCTAssertFalse(text.contains("0 cores"))
    }
    func testAppliedFilterAndDetailNavigationStayVisible() {
        var state=populated();state.setSearch("no_match_123")
        let filtered=TerminalRenderer.render(state,width:80,height:24)
        XCTAssertTrue(filtered.lines.joined().contains("Filter /no_match_123"))
        XCTAssertTrue(filtered.lines.last!.contains("q quit"))
        state.setSearch("");state.detailVisible=true
        let detail=TerminalRenderer.render(state,width:100,height:30).lines.joined()
        XCTAssertTrue(detail.contains("1–1/1 processes"))
        XCTAssertTrue(detail.contains("↑↓ process"))
    }
    func testPartialTotalsRemainMarkedInInspectorAndDetails() {
        var s=populated().snapshots.last!
        s.processes=Array(s.processes.prefix(2))
        s.processes[1].applicationID=s.processes[0].applicationID
        s.processes[1].cpuCores=nil;s.processes[1].footprintBytes=nil
        var state=TerminalState();state.accept(s)
        let wide=TerminalRenderer.render(state,width:160,height:45).lines.joined()
        XCTAssertTrue(wide.contains("1.50* cores"))
        XCTAssertTrue(wide.contains("60.0 MiB*"))
        state.detailVisible=true
        let detail=TerminalRenderer.render(state,width:80,height:24).lines.joined()
        XCTAssertTrue(detail.contains("CPU 1.50*"))
        XCTAssertTrue(detail.contains("60.0 MiB*"))
    }
    func testPressureStripMarksTheSameCollectionGapAsOtherPlots() {
        var state=TerminalState()
        for t in [0.0,60.0] {
            var s=Snapshot(timestamp:Date(timeIntervalSince1970:t),monotonicTime:t)
            s.pressure = .normal;state.accept(s)
        }
        let frame=TerminalRenderer.render(state,width:100,height:30)
        XCTAssertTrue(frame.lines.joined().contains("▁·▁"))
    }
}
