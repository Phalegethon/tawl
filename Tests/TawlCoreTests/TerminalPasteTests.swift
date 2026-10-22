import XCTest
@testable import TawlCore

final class TerminalPasteTests: XCTestCase {
    let start = Array("\u{1b}[200~".utf8)
    let end = Array("\u{1b}[201~".utf8)
    let commands = Array("x\t\r\nq\u{1b}[C\r\u{1b}[D\u{1b}[A".utf8)

    func testPasteNeverEmitsCommandsAndFollowingKeyboardInputStillWorks() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed(start + commands + end), [])
        XCTAssertEqual(input.feed(Array("x\t\r".utf8)), [.text("x"), .tab, .enter])
    }
    func testEveryPossibleSplitIncludingDelimitersRemainsNonInteractive() {
        let paste = start + commands + end
        for split in 0...paste.count {
            var input = TerminalInput()
            XCTAssertEqual(input.feed(Array(paste.prefix(split))), [], "split \(split)")
            XCTAssertEqual(input.feed(Array(paste.dropFirst(split))), [], "split \(split)")
            XCTAssertEqual(input.feed([113]), [.text("q")])
        }
    }
    func testSingleByteDeliveryAndFalseEndPrefixesDoNotLeakPasteCommands() {
        var input = TerminalInput()
        let payload = commands + Array("\u{1b}[20x\u{1b}[201x\u{1b}\u{1b}[201X\t\r".utf8)
        for byte in start + payload + end {
            XCTAssertEqual(input.feed([byte]), [])
        }
        XCTAssertEqual(input.feed(Array("\u{1b}[C".utf8)), [.right])
    }
    func testEscapeFlushInsidePasteDoesNotCancelOrExposeBufferedBytes() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed(start + commands + [27]), [])
        XCTAssertEqual(input.flushEscape(), [])
        XCTAssertEqual(input.feed(Array("[201~".utf8)), [])
        XCTAssertEqual(input.feed([27]), [])
        XCTAssertEqual(input.flushEscape(), [.escape])
    }
    func testLargeAndUnterminatedPasteRemainSuppressedAcrossCalls() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed(start), [])
        XCTAssertEqual(input.feed(Array(repeating: UInt8(9), count: 1_000_000)), [])
        for _ in 0..<32 { XCTAssertEqual(input.feed(commands), []) }
        XCTAssertEqual(input.flushEscape(), [])
        XCTAssertEqual(input.feed(end + [13]), [.enter])
    }
    func testConsecutivePastesAndOrdinaryUTF8KeysDoNotInterfere() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed(start + commands + end + start + commands + end), [])
        XCTAssertEqual(input.feed([0xc3]), [])
        XCTAssertEqual(input.feed([0xa9]), [.text("é")])
    }
}
