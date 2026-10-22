import XCTest
@testable import TawlCore

final class ClosureControlTests: XCTestCase {
    func state(_ snapshot:Snapshot? = nil)->TerminalState {
        var s=TerminalState(); s.accept(snapshot ?? TerminalClosureTests().snapshot()); return s
    }
    func testRootXShowsProcessChoiceWithoutPreparingOrSending() {
        var s=state(); let spy=ClosureControllerSpy()
        s.openClosureControl(now:101)
        XCTAssertTrue(s.closureControlVisible); XCTAssertFalse(s.detailVisible)
        XCTAssertNil(s.closureSession); XCTAssertTrue(spy.prepared.isEmpty)
        let text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("SÜREÇ KAPATMA")); XCTAssertTrue(text.contains("Browser"))
        XCTAssertTrue(text.contains("Enter / i: etkiyi incele"))
        s.prepareControlledClosure(using:spy,now:101)
        XCTAssertEqual(spy.prepared.count,1); XCTAssertEqual(s.closureSession?.intent.pid,42)
        XCTAssertTrue(spy.submitted.isEmpty)
        s.dismissClosure(using:spy)
        XCTAssertTrue(s.closureControlVisible); XCTAssertNil(s.closureSession)
    }
    func testManualSelectionIsEnabledButHistoryKeepsVisibleBlock() {
        var snap=TerminalClosureTests().snapshot(); snap.pressure = .normal
        var s=state(snap); let spy=ClosureControllerSpy()
        s.openClosureControl(now:101)
        var text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("MANUEL")); XCTAssertTrue(text.contains("otomatik öneri yok"))
        XCTAssertTrue(s.closureControlRows.allSatisfy(\.eligible))
        s.prepareControlledClosure(using:spy,now:101)
        XCTAssertNotNil(s.closureSession); XCTAssertEqual(spy.prepared.count,1)
        s.dismissClosure(using:spy)
        s.closeClosureControl(); s.toggleFrozen(); s.openClosureControl(now:101)
        s.prepareControlledClosure(using:spy,now:101)
        text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("canlı ölçüm")); XCTAssertEqual(spy.prepared.count,1)
        XCTAssertTrue(text.contains("Space ile canlı ölçüme geç"))
        s.toggleHistory()
        text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("h, ardından Space ile canlı ölçüme geç"))
    }
    func testRecommendationsRemainPrioritizedAndAllScopeExcludesManualRows() {
        var snap=TerminalClosureTests().snapshot()
        snap.processes[0].footprintBytes=104_857_600
        var s=state(snap); s.openClosureControl(now:101)
        XCTAssertEqual(s.closureControlSelectedID,"43:101")
        XCTAssertEqual(s.closureControlRows.map(\.badge),["ÖNERİ","MANUEL"])
        s.toggleClosureControlScope()
        XCTAssertEqual(s.closureControlRows.map(\.process.pid),[43])
        s.toggleClosureControlScope()
        XCTAssertEqual(s.closureControlRows.count,2)
    }
    func testNativeFailureRemainsInControlAndSelectionDoesNotPrepare() {
        var s=state(); let spy=ClosureControllerSpy(); spy.failure="Sentetik yerel hazırlık başarısız."
        s.openClosureControl(now:101); s.moveClosureControl(by:1)
        XCTAssertTrue(spy.prepared.isEmpty)
        s.prepareControlledClosure(using:spy,now:101)
        XCTAssertTrue(s.closureControlVisible); XCTAssertNil(s.closureSession)
        let text=TerminalRenderer.render(s,width:80,height:24).lines.joined()
        XCTAssertTrue(text.contains("Sentetik yerel hazırlık başarısız.")); XCTAssertTrue(spy.submitted.isEmpty)
        XCTAssertTrue(text.contains("ENGELLİ"))
        XCTAssertTrue(text.contains("yeniden dene"))
        XCTAssertFalse(text.contains("Enter / i: etkiyi incele ve onaya geç"))
        spy.failure = nil
        s.prepareControlledClosure(using:spy,now:101)
        XCTAssertNotNil(s.closureSession)
        XCTAssertTrue(spy.submitted.isEmpty)
    }
    func testSelectedIdentityCannotSilentlyBecomeAnotherCandidate() {
        var s=state(); let spy=ClosureControllerSpy(); s.openClosureControl(now:101)
        let original=s.closureControlSelectedID
        var next=TerminalClosureTests().snapshot(102); next.processes.removeAll{$0.id==original}
        s.accept(next); s.prepareControlledClosure(using:spy,now:102)
        XCTAssertEqual(s.closureControlSelectedID,original)
        XCTAssertNil(s.closureSession); XCTAssertTrue(spy.prepared.isEmpty)
        XCTAssertTrue(s.closureControlMessage.contains("ölçümde yok"))
    }
    func testAllRecommendationsScopeFindsOtherApplications() {
        var snap=TerminalClosureTests().snapshot()
        var other=snap.processes[0]; other.id="99:101";other.pid=99;other.applicationID="app:Other";other.applicationName="Other App"
        snap.processes.append(other)
        var s=state(snap);s.openClosureControl(now:101)
        XCTAssertFalse(s.closureControlRows.contains{$0.process.pid==99})
        s.toggleClosureControlScope()
        XCTAssertTrue(s.closureControlRows.contains{$0.process.pid==99})
    }
    func testControlCaptureWhenRequested() throws {
        guard let dir=ProcessInfo.processInfo.environment["TAWL_CONTROL_CAPTURE"] else{return}
        try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
        func save(_ s:TerminalState,_ w:Int,_ h:Int,_ name:String)throws{
            let f=TerminalRenderer.render(s,width:w,height:h)
            XCTAssertEqual(f.lines.count,h);XCTAssertTrue(f.lines.allSatisfy{TerminalText.width($0)<=w})
            try f.coloredLines.joined(separator:"\n").write(toFile:"\(dir)/\(name).ansi",atomically:true,encoding:.utf8)
        }
        var s=state();s.openClosureControl(now:101)
        for(w,h) in [(80,24),(100,30),(143,45),(160,68)]{try save(s,w,h,"control-\(w)x\(h)")}
        var snap=TerminalClosureTests().snapshot();snap.pressure = .normal
        var manual=state(snap);manual.openClosureControl(now:101)
        try save(manual,80,24,"control-manual-80x24")
        for i in snap.processes.indices {snap.processes[i].canReviewClosure=false}
        var blocked=state(snap);blocked.openClosureControl(now:101)
        try save(blocked,80,24,"control-blocked-80x24")
        blocked.toggleFrozen();try save(blocked,143,45,"control-history-143x45")
        let spy=ClosureControllerSpy();spy.failure="Sentetik yerel hazırlık başarısız."
        s.prepareControlledClosure(using:spy,now:101);try save(s,80,24,"control-error-80x24")
        var populated=TerminalClosureTests().snapshot()
        for i in 0..<36 {
            var p=populated.processes[0];p.pid=Int32(100+i);p.id="\(p.pid):101"
            p.name="Browser Helper — pencere \(i)";p.footprintBytes=UInt64(100_000_000+i*100_000_000)
            populated.processes.append(p)
        }
        var many=state(populated);many.openClosureControl(now:101)
        try save(many,143,45,"control-populated-143x45")
        for i in populated.processes.indices {populated.processes[i].applicationName=String(repeating:"Çok uzun uygulama ",count:12)}
        many=state(populated);many.openClosureControl(now:101)
        try save(many,80,24,"control-long-80x24")
        many.prepareControlledClosure(using:ClosureControllerSpy(),now:101)
        try save(many,80,24,"control-confirm-long-80x24")
    }
    func testExportOverlayRetainsComparisonAndErrorsAreRecoverable() throws {
        var (s,_)=ClosureImpactUITests().submitted()
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:dir)}
        s.exportImpact(directory:dir)
        XCTAssertTrue(s.impactExportVisible);XCTAssertNotNil(s.impactExportURL)
        XCTAssertTrue(s.impactExportError.isEmpty)
        let first=s.impactExportURL!,before=try Data(contentsOf:first)
        XCTAssertTrue(TerminalRenderer.render(s,width:80,height:24).lines.joined().contains("HTML RAPOR KAYDEDİLDİ"))
        s.captureImpact(ClosureImpactUITests().sample(102,after:true),now:102)
        s.exportImpact(directory:dir)
        XCTAssertNotEqual(s.impactExportURL,first);XCTAssertEqual(try Data(contentsOf:first),before)
        XCTAssertEqual(s.closureImpact?.startedAt,100)
        s.exportImpact(directory:first)
        XCTAssertNil(s.impactExportURL);XCTAssertFalse(s.impactExportError.isEmpty)
        XCTAssertNotNil(s.closureImpact)
        if let capture=ProcessInfo.processInfo.environment["TAWL_CONTROL_CAPTURE"] {
            func save(_ name:String)throws{
                try TerminalRenderer.render(s,width:80,height:24).coloredLines.joined(separator:"\n").write(toFile:"\(capture)/\(name).ansi",atomically:true,encoding:.utf8)
            }
            try FileManager.default.createDirectory(atPath:capture,withIntermediateDirectories:true)
            try save("export-error-80x24")
            s.exportImpact(directory:dir);try save("export-success-80x24")
        }
    }
}
