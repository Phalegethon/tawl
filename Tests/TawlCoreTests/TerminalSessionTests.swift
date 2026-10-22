import XCTest
@testable import TawlCore

final class TerminalSessionTests: XCTestCase {
    func testSGRWheelDecodesSplitReportsAndModifiers() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed(Array("\u{1b}[<64;12".utf8)), [])
        XCTAssertEqual(input.feed(Array(";9M\u{1b}[<65;12;9M".utf8)), [.up, .down])
        XCTAssertEqual(input.feed(Array("\u{1b}[<92;999;200M\u{1b}[<93;1;1M".utf8)), [.up, .down])
        XCTAssertEqual(input.feed(Array("\u{1b}[Aq".utf8)), [.up, .text("q")])
    }

    func testMouseClicksReleasesAndMalformedReportsCannotBecomeCommands() {
        var input = TerminalInput()
        let reports = "\u{1b}[<0;113;113M\u{1b}[<0;113;113m\u{1b}[<65;0;1M" +
            "\u{1b}[<65;1;1m\u{1b}[<66;1;1M\u{1b}[<96;1;1M\u{1b}[<9999999999999999999999;1;1M"
        XCTAssertEqual(input.feed(Array(reports.utf8)), [])
        XCTAssertEqual(input.feed(Array("b".utf8)), [.text("b")])
    }

    func testLegacyMousePayloadIsConsumedEvenWhenCoordinatesLookLikeKeys() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed([27,91,77,96]), [])
        XCTAssertEqual(input.feed([113,113]), [.up])
        XCTAssertEqual(input.feed([27,91,77,97,113,113]), [.down])
        XCTAssertEqual(input.feed([27,91,77,32,113,113]), [])
        XCTAssertEqual(input.feed([113]), [.text("q")])
    }

    func testFullWidthFramesUsePositioningInsteadOfScrollProducingLinefeeds() {
        var state = TerminalState()
        state.accept(Snapshot(timestamp: Date(), monotonicTime: 1))
        for (width, height) in [(80,24),(100,30),(160,45)] {
            let frame = TerminalRenderer.render(state, width:width, height:height)
            for colors in [false, true] {
                let output = TerminalUI.screenOutput(frame, colors:colors)
                XCTAssertFalse(output.contains("\n"))
                XCTAssertFalse(output.contains("\r"))
                XCTAssertTrue(output.hasPrefix("\u{1b}[1;1H"))
                XCTAssertTrue(output.contains("\u{1b}[\(height);1H"))
                XCTAssertFalse(output.contains("\u{1b}[\(height+1);1H"))
                XCTAssertFalse(output.contains("\u{1b}[S"))
            }
        }
    }
}
