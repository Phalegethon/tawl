import XCTest
@testable import TawlCore

final class LocalizationUITests: XCTestCase {
    private let viewports = [(80,24),(100,30),(157,43)]

    func testClockKeepsFixedEnglishDigitsInEitherLanguage() {
        XCTAssertEqual(TerminalRenderer.clock.locale.identifier,"en_US_POSIX")
        for language in AppLanguage.allCases {
            L10n.withLanguage(language) {
                let value = TerminalRenderer.time(Date(timeIntervalSince1970:1_790_000_000))
                XCTAssertNotNil(value.range(of:"^[0-9]{2}:[0-9]{2}:[0-9]{2}$",options:.regularExpression))
            }
        }
    }

    func testBothLanguagesKeepHardwareSortHeadersAndQuitActionVisible() {
        for (language,footprint,members,quit) in [
            (AppLanguage.english,"3 FOOTPRINT↓","5 MEMBERS↓","q quit"),
            (.turkish,"3 AYAK İZİ↓","5 ÜYE↓","q çıkış")
        ] {
            L10n.withLanguage(language) {
                var state = HardwareViewTests().populated()
                state.chooseSort(.footprint)
                let selectedID = state.selectedID
                for (width,height) in viewports {
                    let frame = TerminalRenderer.render(state,width:width,height:height)
                    let text = frame.lines.joined(separator:"\n")
                    XCTAssertTrue(text.contains(footprint),"Missing sort header: \(language) \(width)x\(height)")
                    XCTAssertTrue(text.contains("GPU"))
                    for core in 1...12 {
                        XCTAssertTrue(text.contains(String(format:"%02d",core)+(core<=4 ? "E":"P")))
                    }
                    XCTAssertTrue(frame.lines.last!.contains("g CPU/GPU"))
                    XCTAssertTrue(frame.lines.last!.contains(quit))
                    XCTAssertGreaterThanOrEqual(frame.visibleRowIDs.count,6)
                    XCTAssertTrue(frame.lines.allSatisfy { TerminalText.width($0) == width })
                    XCTAssertEqual(state.selectedID,selectedID)
                }
                state.chooseSort(.members)
                for (width,height) in viewports {
                    let frame = TerminalRenderer.render(state,width:width,height:height)
                    XCTAssertTrue(frame.lines.joined().contains(members),"Member header and direction must fit together")
                }
            }
        }
    }

    func testLanguageDoesNotChangeTerminationEligibilityOrSelectedIdentity() {
        var initial = TerminalClosureTests().state()
        initial.openClosureControl(now:101)
        let english = L10n.withLanguage(.english) {
            (initial.closureControlRows.filter(\.eligible).map { $0.process.id },initial.selectedControlRow?.process.id)
        }
        let turkish = L10n.withLanguage(.turkish) {
            (initial.closureControlRows.filter(\.eligible).map { $0.process.id },initial.selectedControlRow?.process.id)
        }
        XCTAssertEqual(english.0,turkish.0)
        XCTAssertEqual(english.1,turkish.1)
        XCTAssertFalse(english.0.isEmpty)
        for (language,title,action) in [
            (AppLanguage.english,"PROCESS TERMINATION","Enter / i: review impact"),
            (.turkish,"SÜREÇ KAPATMA","Enter / i: etkiyi incele")
        ] {
            L10n.withLanguage(language) {
                for (width,height) in viewports {
                    let frame = TerminalRenderer.render(initial,width:width,height:height)
                    let text = frame.lines.joined(separator:"\n")
                    XCTAssertTrue(text.contains(title))
                    XCTAssertTrue(text.contains(action))
                    XCTAssertTrue(text.contains(initial.selectedControlRow!.process.applicationName))
                    XCTAssertEqual(frame.visibleRowIDs.contains(english.1!),true)
                    XCTAssertTrue(frame.lines.allSatisfy { TerminalText.width($0) == width })
                }
            }
        }
    }

    func testBothLanguagesKeepExplicitConfirmationAndComparisonActionsVisible() {
        for (language,cancel,send,save,quit) in [
            (AppLanguage.english,"› Cancel","Send termination request","d: save HTML report","q quit"),
            (.turkish,"› Vazgeç","Sonlandırma isteği gönder","d: HTML raporu kaydet","q çıkış")
        ] {
            L10n.withLanguage(language) {
                for (width,height) in viewports {
                    var state = TerminalClosureTests().state()
                    let controller = ClosureControllerSpy()
                    state.beginClosure(using:controller,now:101)
                    let first = TerminalRenderer.render(state,width:width,height:height)
                    state.scrollClosure(by:1000,limit:first.maximumDetailScroll)
                    let confirmation = TerminalRenderer.render(state,width:width,height:height)
                    let text = confirmation.lines.joined(separator:"\n")
                    XCTAssertTrue(text.contains(cancel))
                    XCTAssertTrue(text.contains(send))
                    XCTAssertTrue(text.contains("Enter/Space"))
                    XCTAssertTrue(confirmation.lines.last!.contains(quit))
                    XCTAssertEqual(state.closureSession?.choice,.cancel)
                    XCTAssertTrue(controller.submitted.isEmpty)
                    XCTAssertTrue(confirmation.lines.allSatisfy { TerminalText.width($0) == width })

                    let (comparison,_) = ClosureImpactUITests().submitted()
                    let result = TerminalRenderer.render(comparison,width:width,height:height)
                    XCTAssertTrue(result.lines.last!.contains(save))
                    XCTAssertTrue(result.lines.last!.contains(quit))
                    XCTAssertTrue(result.lines.allSatisfy { TerminalText.width($0) == width })
                }
            }
        }
    }
    func testCaptureBilingualStatesWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["TAWL_LOCALIZATION_CAPTURE"] else { return }
        let directory = URL(fileURLWithPath:path,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        func save(_ state:TerminalState,_ width:Int,_ height:Int,_ name:String) throws {
            let frame = TerminalRenderer.render(state,width:width,height:height)
            try frame.coloredLines.joined(separator:"\n").write(to:directory.appendingPathComponent(name+".ansi"),atomically:true,encoding:.utf8)
            try frame.lines.joined(separator:"\n").write(to:directory.appendingPathComponent(name+".txt"),atomically:true,encoding:.utf8)
        }
        for language in AppLanguage.allCases {
            try L10n.withLanguage(language) {
                var dashboard = HardwareViewTests().populated()
                dashboard.chooseSort(.footprint)
                for (width,height) in [(80,24),(157,43)] {
                    try save(dashboard,width,height,"\(language.rawValue)-hardware-\(width)x\(height)")
                }
                var confirmation = TerminalClosureTests().state()
                let controller = ClosureControllerSpy()
                confirmation.beginClosure(using:controller,now:101)
                try save(confirmation,80,24,"\(language.rawValue)-confirmation-start-80x24")
                let frame = TerminalRenderer.render(confirmation,width:80,height:24)
                confirmation.scrollClosure(by:1000,limit:frame.maximumDetailScroll)
                try save(confirmation,80,24,"\(language.rawValue)-confirmation-ready-80x24")
                XCTAssertTrue(controller.submitted.isEmpty)
            }
        }
    }

}
