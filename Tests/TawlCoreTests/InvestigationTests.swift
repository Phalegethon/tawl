import XCTest
@testable import TawlCore

final class InvestigationTests:XCTestCase {
    func snapshot(_ t:Double,count:Int=25)->Snapshot {
        var s=Snapshot(timestamp:Date(timeIntervalSince1970:1_790_000_000+t),monotonicTime:t)
        s.intervalSeconds=2;s.logicalCPUCount=12;s.cpuPercent=30;s.pressure = .warning
        s.processes=(0..<count).map { index -> ProcessSample in
            let name: String = index == 0 ? "Render worker" : "Task \(index)"
            let cpu: Double = index == 0 ? 2.5 : 0.001
            let footprint: UInt64 = index == 0 ? 5_368_709_120 : 536_870_912
            return ProcessSample(
                id: "\(index):100", pid: Int32(100 + index), name: name,
                applicationID: "app:fixture", applicationName: "Test Editor (sentetik)",
                projectID: nil, projectName: nil, projectEvidence: nil,
                cpuCores: cpu, footprintBytes: footprint, memoryDeltaBytes: 0,
                diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0,
                ageSeconds: 10_000 + t, canReviewClosure: true)
        }
        s.totalProcessCount=count;return s
    }
    func testDetailsKeepUsefulRowsAndBoundNumbersNearTheirProcess() {
        var state=TerminalState();state.accept(snapshot(0));state.openDetails()
        for (w,h,minimum) in [(80,24,6),(100,30,10),(143,68,20),(160,45,20)] {
            let frame=TerminalRenderer.render(state,width:w,height:h)
            XCTAssertGreaterThanOrEqual(frame.visibleRowIDs.count,minimum)
            XCTAssertTrue(frame.lines.allSatisfy{TerminalText.width($0)<=w})
            XCTAssertTrue(frame.lines.joined().contains("CPU+RAM!"))
            XCTAssertFalse(frame.lines.joined().contains("Kimlik 100:"))
            XCTAssertTrue(frame.lines.last!.contains("q çıkış"))
            let header=frame.lines.first{$0.contains("1 SÜREÇ") && $0.contains("2 CPU") }!
            let location=header.distance(from:header.startIndex,to:header.range(of:"2 CPU")!.lowerBound)
            XCTAssertLessThan(location,68)
        }
    }
    func testManualSortAndMemberSelectionSurviveChangingMetrics() {
        var state=TerminalState();state.accept(snapshot(0));state.openDetails();state.moveProcess(by:3)
        let selected=state.selectedProcess?.id
        state.chooseSort(.name);XCTAssertEqual(state.sortDirection,.ascending)
        state.chooseSort(.name);XCTAssertEqual(state.sortDirection,.descending)
        state.chooseSort(.memoryDelta)
        var next=snapshot(2);next.processes[3].memoryDeltaBytes=200_000_000
        state.accept(next)
        XCTAssertEqual(state.selectedProcess?.id,selected)
        XCTAssertTrue(TerminalRenderer.render(state,width:80,height:24).visibleRowIDs.contains(selected!))
        XCTAssertTrue(TerminalRenderer.render(state,width:100,height:30).lines.joined().contains("4 Δ BELLEK↓"))
    }
    func testThreeGroupingModesAndRecommendationFilterAreDiscoverable() {
        var state=TerminalState();state.accept(snapshot(0));state.toggleGrouping()
        XCTAssertEqual(state.grouping,.project);state.toggleGrouping()
        XCTAssertEqual(state.grouping,.category)
        XCTAssertTrue(TerminalRenderer.render(state,width:100,height:30).lines.joined().contains("KULLANIM ALANLARI"))
        state.toggleGrouping();XCTAssertEqual(state.grouping,.application)
        state.openDetails();state.toggleRecommendations()
        XCTAssertEqual(state.visibleProcesses.map(\.pid),[100])
        XCTAssertTrue(TerminalRenderer.render(state,width:100,height:30).lines.joined().contains("ÖNERİLER"))
    }
    func testQuietCandidatesUseCompactEvidenceAndHistoricalModeIsClearlyLabeled() {
        var state=TerminalState()
        for t in stride(from:0.0,through:620,by:2) {state.accept(snapshot(t,count:2))}
        state.openDetails();state.moveProcess(by:1)
        XCTAssertTrue(state.assessment(for:state.selectedProcess!).recommendations.contains{$0.kind == .quietMemory})
        state.processInfoVisible=true
        let live=TerminalRenderer.render(state,width:100,height:45).lines.joined()
        XCTAssertTrue(live.contains("UZUN SÜREDİR AÇIK"))
        state.toggleFrozen()
        XCTAssertTrue(state.assessment(for:state.selectedProcess!).recommendations.contains{$0.kind == .quietMemory})
        var busy=snapshot(622,count:2);busy.processes[1].cpuCores=3
        state.accept(busy)
        XCTAssertTrue(state.assessment(for:state.selectedProcess!).recommendations.contains{$0.kind == .quietMemory})
        let frozen=TerminalRenderer.render(state,width:100,height:45).lines.joined()
        XCTAssertTrue(frozen.contains("CANLI KARAR DEĞİL"))
        state.toggleHistory()
        XCTAssertTrue(state.assessment(for:state.selectedProcess!).recommendations.contains{$0.kind == .quietMemory})
        state.toggleHistory();state.toggleFrozen()
        XCTAssertFalse(state.assessment(for:state.selectedProcess!).recommendations.contains{$0.kind == .quietMemory})
    }
    func testRecommendationSelectionTracksVisibleCandidates() {
        var state=TerminalState();var first=snapshot(0,count:2)
        first.processes[1].footprintBytes=3_221_225_472
        state.accept(first);state.openDetails();state.toggleRecommendations()
        XCTAssertEqual(state.selectedProcess?.pid,100)
        var next=first;next.monotonicTime=2;next.processes[0].footprintBytes=100_000_000
        state.accept(next)
        XCTAssertEqual(state.visibleProcesses.map(\.pid),[101])
        XCTAssertEqual(state.selectedProcess?.pid,101)
        next.monotonicTime=4;next.processes[1].footprintBytes=100_000_000
        state.accept(next)
        XCTAssertTrue(state.visibleProcesses.isEmpty)
        XCTAssertNil(state.selectedProcess)
    }
    func testActualAndSyntheticReviewFrames() throws {
        guard let directory=ProcessInfo.processInfo.environment["TAWL_CAPTURE_DIR"],let record=ProcessInfo.processInfo.environment["TAWL_CAPTURE_RECORD"] else {return}
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        func save(_ state:TerminalState,_ w:Int,_ h:Int,_ name:String) throws {
            let frame=TerminalRenderer.render(state,width:w,height:h)
            try frame.coloredLines.joined(separator:"\n").write(toFile:directory+"/"+name+".ansi",atomically:true,encoding:.utf8)
            try frame.lines.joined(separator:"\n").write(toFile:directory+"/"+name+".txt",atomically:true,encoding:.utf8)
        }
        var state=TerminalState()
        for s in try RecordingReader.read(url:URL(fileURLWithPath:record)).snapshots {state.accept(s)}
        state.chooseSort(.footprint);state.moveSelection(by:-10000);state.toggleHistory()
        try save(state,143,68,"main-143x68")
        state.openDetails()
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] {try save(state,w,h,"processes-\(w)x\(h)")}
        state.processInfoVisible=true;try save(state,100,45,"evidence-100x45")
        state.toggleGrouping();state.toggleGrouping();try save(state,143,68,"categories-143x68")
        var synthetic=TerminalState()
        for t in stride(from:0.0,through:620,by:2) {synthetic.accept(snapshot(t))}
        synthetic.notice="SENTETİK SENARYO · eşik ve öneri görünümü testi"
        synthetic.openDetails();synthetic.toggleRecommendations()
        try save(synthetic,143,45,"synthetic-candidates-143x45")
        synthetic.moveProcess(by:1);synthetic.processInfoVisible=true
        try save(synthetic,100,45,"synthetic-quiet-100x45")
    }
}
