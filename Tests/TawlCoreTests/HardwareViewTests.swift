import XCTest
@testable import TawlCore

final class HardwareViewTests:XCTestCase {
    func populated(count:Int=12,gpus:Int=1)->TerminalState {
        var state=TerminalState();state.hardwareVisible=true
        var s=DashboardTests().populated().snapshots.last!
        s.logicalCPUCount=count
        for t in stride(from:100.0,through:160,by:2) {
            s.monotonicTime=t;s.timestamp=Date(timeIntervalSince1970:t)
            s.cpuCores=(0..<count).map { id in
                CPUCoreSample(id:id,kind:id<4 ? .efficiency:.performance,
                              utilizationPercent:id==0 ? 98 : Double((id*13+Int(t))%80))
            }
            s.gpus=(0..<gpus).map{GPUSample(id:"gpu\($0)",name:"Apple M2 Max",coreCount:38,utilizationPercent:Double(Int(t)%90))}
            state.accept(s)
        }
        return state
    }
    func testAllTwelveCoresAndGPUFitBesideUsefulWorkloadRows() {
        for (w,h,minRows) in [(80,24,6),(100,30,10),(157,43,18),(160,68,30)] {
            let frame=TerminalRenderer.render(populated(),width:w,height:h)
            let text=frame.lines.joined(separator:"\n")
            for id in 1...12 { XCTAssertTrue(text.contains(String(format:"%02d",id)+(id<=4 ? "E":"P")),"Core \(id) missing in \(w)x\(h)") }
            XCTAssertTrue(text.contains("GPU"));XCTAssertTrue(text.contains("38"))
            XCTAssertTrue(text.lowercased(with:Locale(identifier:"en_US_POSIX")).contains("device total"))
            XCTAssertTrue(text.contains("0–100%"));XCTAssertTrue(text.contains("MEMORY"))
            XCTAssertGreaterThanOrEqual(frame.visibleRowIDs.count,minRows)
            XCTAssertTrue(frame.lines.allSatisfy{TerminalText.width($0)<=w})
            XCTAssertEqual(frame.lines.count,h)
            XCTAssertTrue(frame.lines.last!.contains("g CPU/GPU"));XCTAssertTrue(frame.lines.last!.contains("q quit"))
            XCTAssertTrue(frame.coloredLines.joined().contains("38;5;203"),"Hot core must be visible without changing scale")
        }
    }
    func testTogglePreservesSelectionAndPinnedHardwareHistory() {
        var state=populated();state.moveSelection(by:3);let selected=state.selectedID
        state.toggleFrozen()
        let before=TerminalRenderer.render(state,width:157,height:43)
        var next=state.snapshots.last!;next.monotonicTime+=2
        next.cpuCores=[CPUCoreSample(id:0,kind:.efficiency,utilizationPercent:0)]
        next.gpus=[];state.accept(next)
        let after=TerminalRenderer.render(state,width:157,height:43)
        XCTAssertEqual(Array(before.lines[3..<18]),Array(after.lines[3..<18]))
        state.toggleHardware();XCTAssertFalse(state.hardwareVisible)
        XCTAssertTrue(TerminalRenderer.render(state,width:157,height:43).lines.joined().contains("System total"))
        state.toggleHardware();XCTAssertTrue(state.hardwareVisible)
        XCTAssertEqual(state.selectedID,selected);XCTAssertTrue(state.frozen)
        state.toggleFrozen();state.toggleHistory();state.moveHistory(by:-1)
        XCTAssertEqual(state.visibleSnapshot?.cpuCores?.count,12)
    }
    func testEveryCoreAndGPUReachableThroughBoundedPages() {
        var state=populated(count:128,gpus:4)
        let layout=HardwareLayout(snapshot:state.visibleSnapshot!,width:80,height:24)
        XCTAssertGreaterThan(layout.pages,1)
        var text=""
        for page in 0..<layout.pages {
            state.hardwarePage=page
            let f=TerminalRenderer.render(state,width:80,height:24)
            text+=f.lines.joined(separator:"\n")
            XCTAssertGreaterThanOrEqual(f.visibleRowIDs.count,6)
            XCTAssertTrue(f.lines.joined().contains("[ ]"))
        }
        for id in 1...128 {XCTAssertTrue(text.contains(String(format:"%02d",id)+(id<=4 ? "E":"P")))}
        for id in 1...4 {XCTAssertTrue(text.contains("GPU \(id)/4"))}
    }
    func testPagingAfterResizeMovesImmediatelyFromVisiblePage() {
        var state=populated(count:128,gpus:4);state.hardwarePage=100
        let layout=HardwareLayout(snapshot:state.visibleSnapshot!,width:160,height:68)
        state.moveHardwarePage(by:-1,width:160,height:68)
        XCTAssertEqual(state.hardwarePage,layout.pages-2)
        state.moveHardwarePage(by:100,width:160,height:68)
        XCTAssertEqual(state.hardwarePage,layout.pages-1)
    }
    func testMissingAndLongNamesStayExplicitAndBounded() throws {
        var state=populated();var s=state.visibleSnapshot!;s.monotonicTime+=2
        s.cpuCores=nil;s.gpus=nil;state.accept(s)
        let missing=TerminalRenderer.render(state,width:80,height:24).lines.joined()
        XCTAssertTrue(missing.contains("No core measurements"));XCTAssertTrue(missing.contains("GPU · no measurements"))
        s.monotonicTime+=2
        s.cpuCores=[CPUCoreSample(id:0,kind:.unknown,utilizationPercent:nil)]
        s.gpus=[GPUSample(id:"long",name:String(repeating:"Long GPU 名 ",count:20),utilizationPercent:nil)]
        state.accept(s)
        let f=TerminalRenderer.render(state,width:80,height:24)
        XCTAssertTrue(f.lines.joined().contains("01?"));XCTAssertTrue(f.lines.joined().contains("—"))
        XCTAssertTrue(f.lines.allSatisfy{TerminalText.width($0)<=80})
    }
    func testCaptureHardwareStatesWhenRequested() throws {
        guard let path=ProcessInfo.processInfo.environment["TAWL_HARDWARE_CAPTURE"] else{return}
        let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        func save(_ state:TerminalState,_ w:Int,_ h:Int,_ name:String)throws {
            let f=TerminalRenderer.render(state,width:w,height:h)
            try f.coloredLines.joined(separator:"\n").write(to:dir.appendingPathComponent(name+".ansi"),atomically:true,encoding:.utf8)
            try f.lines.joined(separator:"\n").write(to:dir.appendingPathComponent(name+".txt"),atomically:true,encoding:.utf8)
        }
        for (w,h) in [(80,24),(100,30),(157,43),(160,68)]{try save(populated(),w,h,"hardware-\(w)x\(h)")}
        var missing=populated();var s=missing.visibleSnapshot!;s.cpuCores=nil;s.gpus=nil;s.monotonicTime+=2;missing.accept(s)
        try save(missing,80,24,"hardware-missing")
        var many=populated(count:128,gpus:4);many.hardwarePage=8
        try save(many,80,24,"hardware-many")
        var live=TerminalState();live.hardwareVisible=true;let collector=NativeCollector();let reducer=SnapshotReducer()
        live.accept(reducer.reduce(collector.collect()));Thread.sleep(forTimeInterval:0.12)
        live.accept(reducer.reduce(collector.collect()));try save(live,157,43,"hardware-live")
    }
}
