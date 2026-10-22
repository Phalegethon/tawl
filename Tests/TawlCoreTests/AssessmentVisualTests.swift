import XCTest
@testable import TawlCore

final class AssessmentVisualTests:XCTestCase {
    func state(quiet:Bool=false)->TerminalState {
        var state=TerminalState()
        for t in stride(from:0.0,through:quiet ? 620:30,by:2) {
            var s=InvestigationTests().snapshot(t,count:25)
            s.swapUsedBytes=10_737_418_240+UInt64(t)*100_000
            s.swapInBytesPerSecond=0;s.swapOutBytesPerSecond=100_000
            state.accept(s)
        }
        state.openDetails()
        if quiet {state.moveProcess(by:1)}
        return state
    }
    func testEvaluationShowsMeasuredChartsDurationAndContextAcrossSizes() {
        var state=state(quiet:true);state.processInfoVisible=true
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] {
            let frame=TerminalRenderer.render(state,width:w,height:h)
            let text=frame.lines.joined(separator:"\n")
            XCTAssertTrue(text.contains("CPU"));XCTAssertTrue(text.contains("FOOTPRINT"))
            XCTAssertTrue(text.contains("OBSERVATION TIME"));XCTAssertTrue(text.contains("600 / 600 s"))
            XCTAssertTrue(text.contains("x: affected application"),"A brief next step must be visible without scrolling")
            XCTAssertTrue(text.contains("512.0 MiB"),"UInt64 measurements must be converted numerically")
            XCTAssertFalse(text.contains("0–1 B"))
            XCTAssertTrue(text.contains("█"),"Actual history and duration must render graph cells")
            XCTAssertEqual(frame.lines.count,h)
            XCTAssertTrue(frame.lines.allSatisfy{TerminalText.width($0)<=w})
            XCTAssertTrue(frame.coloredLines.joined().contains("38;5;"))
            if w>=120 {XCTAssertTrue(text.contains("RAM → disk"));XCTAssertTrue(text.contains("WHAT CAN I DO?"))}
            if w==80 {XCTAssertGreaterThan(frame.maximumDetailScroll,0)}
        }
    }
    func testMemoryFocusKeepsFootprintComparisonAndProcessDrilldown() {
        var state=state();state.toggleMemoryFocus()
        XCTAssertTrue(state.memoryFocus);XCTAssertFalse(state.detailVisible)
        XCTAssertEqual(state.grouping,.application);XCTAssertEqual(state.sort,.footprint)
        for (w,h) in [(80,24),(160,45)] {
            let text=TerminalRenderer.render(state,width:w,height:h).lines.joined()
            XCTAssertTrue(text.contains("SWAP / MEMORY"));XCTAssertTrue(text.contains("MEMORY CANDIDATES"))
            XCTAssertTrue(text.contains("RAM→disk") || text.contains("RAM → disk"))
            XCTAssertTrue(text.contains("Disk→RAM") || text.contains("Disk → RAM"))
            XCTAssertTrue(text.contains("0–10.0 GiB"))
        }
        state.openDetails();XCTAssertFalse(state.memoryFocus);XCTAssertTrue(state.detailVisible)
        state.toggleMemoryFocus();state.toggleGrouping();XCTAssertFalse(state.memoryFocus)
    }
    func testUnknownObservationsStayUnknownAndViewportCopiesStyle() {
        var state=TerminalState();var s=InvestigationTests().snapshot(0,count:1)
        s.processes[0].canReviewClosure=nil;s.processes[0].cpuCores=nil;s.processes[0].footprintBytes=nil
        state.accept(s);state.openDetails();state.processInfoVisible=true
        let frame=TerminalRenderer.render(state,width:100,height:45)
        XCTAssertTrue(frame.lines.joined().contains("no evidence"))
        XCTAssertFalse(frame.lines.joined().contains("0 / 600 s"))
        XCTAssertTrue(frame.lines.joined().contains("Missing measurements"))
        XCTAssertFalse(frame.lines.joined().contains("High usage threshold not exceeded"))
        var source=TerminalCanvas(width:8,height:4)
        source.write("漢A",x:1,y:2,ink:.warning,fill:.panel)
        var target=TerminalCanvas(width:6,height:2)
        target.copy(source,fromRow:2,toX:1,toY:0,rowCount:2)
        XCTAssertTrue(target.lines[0].contains("漢A"))
        XCTAssertTrue(target.ansiLines().joined().contains("38;5;221;48;5;235m"))
        XCTAssertTrue(target.lines.allSatisfy{TerminalText.width($0)==6})
    }
    func testExportVisualAssessmentReview() throws {
        guard let directory=ProcessInfo.processInfo.environment["TAWL_ASSESSMENT_CAPTURE"],let record=ProcessInfo.processInfo.environment["TAWL_CAPTURE_RECORD"] else {return}
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        func save(_ state:TerminalState,_ w:Int,_ h:Int,_ name:String) throws {
            let f=TerminalRenderer.render(state,width:w,height:h)
            try f.coloredLines.joined(separator:"\n").write(toFile:directory+"/"+name+".ansi",atomically:true,encoding:.utf8)
            try f.lines.joined(separator:"\n").write(toFile:directory+"/"+name+".txt",atomically:true,encoding:.utf8)
        }
        var actual=TerminalState()
        for s in try RecordingReader.read(url:URL(fileURLWithPath:record)).snapshots {actual.accept(s)}
        actual.chooseSort(.footprint);actual.moveSelection(by:-10000);actual.toggleHistory();actual.openDetails()
        try save(actual,160,45,"actual-inspector-160x45")
        actual.processInfoVisible=true
        for (w,h) in [(80,24),(100,30),(143,68),(160,45)] {try save(actual,w,h,"actual-assessment-\(w)x\(h)")}
        actual.toggleMemoryFocus()
        for (w,h) in [(80,24),(100,30),(143,68)] {try save(actual,w,h,"actual-swap-\(w)x\(h)")}
        var quiet=state(quiet:true);quiet.processInfoVisible=true;quiet.notice="SYNTHETIC SCENARIO · low activity and swap writes"
        try save(quiet,143,45,"synthetic-quiet-143x45")
        var missing=TerminalState();var s=InvestigationTests().snapshot(0,count:1)
        s.processes[0].canReviewClosure=nil;s.processes[0].cpuCores=nil;s.processes[0].footprintBytes=nil;s.processes[0].ageSeconds=nil
        missing.accept(s);missing.openDetails();missing.processInfoVisible=true;missing.notice="SYNTHETIC SCENARIO · missing measurements"
        try save(missing,100,30,"synthetic-missing-100x30")
    }
}
