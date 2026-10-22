import XCTest
@testable import TawlCore

final class TerminalCanvasTests: XCTestCase {
    func testCanvasClipsWholeUnicodeGlyphsWithoutWrapping() {
        var canvas = TerminalCanvas(width: 7, height: 2)
        canvas.write("界e\u{301}👩🏽‍💻abcdef", x: 1, y: 0)
        canvas.write("界x", x: 6, y: 1)
        XCTAssertEqual(canvas.lines, [" 界e\u{301}👩🏽‍💻a", "       "])
        XCTAssertTrue(canvas.lines.allSatisfy { TerminalText.width($0) == 7 })
    }

    func testOverwriteOfEitherHalfRemovesTheWholeWideGlyph() {
        var canvas = TerminalCanvas(width: 6, height: 2)
        canvas.write("a界bc", x: 0, y: 0)
        canvas.write("!", x: 2, y: 0)
        canvas.write("a界bc", x: 0, y: 1)
        canvas.write("!", x: 1, y: 1)
        XCTAssertEqual(canvas.lines, ["a !bc ", "a! bc "])
    }

    func testNegativeCoordinatesClipRatherThanShiftOrLeavePartialGlyphs() {
        var canvas = TerminalCanvas(width: 4, height: 1)
        canvas.write("界ABCDEF", x: -1, y: 0)
        canvas.write("ignored", x: 0, y: -1)
        canvas.write("ignored", x: 0, y: 1)
        XCTAssertEqual(canvas.lines, [" ABC"])
        XCTAssertEqual(TerminalCanvas(width: -1, height: 2).lines, ["", ""])
        XCTAssertEqual(TerminalCanvas(width: 3, height: -1).lines, [])
    }

    func testUntrustedANSIAndTerminalControlNeverBecomeOutputCommands() {
        var canvas = TerminalCanvas(width: 16, height: 1)
        canvas.write("ok\u{1b}[2J\u{1b}]52;c;secret\u{7}end\n\u{202e}", x: 0, y: 0, ink: .cpu)
        XCTAssertEqual(canvas.lines, ["okend           "])
        XCTAssertEqual(canvas.ansiLines(colors: false), canvas.lines)
        let ansi = canvas.ansiLines().joined()
        XCTAssertFalse(ansi.contains("[2J"))
        XCTAssertFalse(ansi.contains("secret"))
        XCTAssertFalse(ansi.contains("\n"))
        XCTAssertEqual(TerminalText.sanitize(ansi), canvas.lines.joined())
    }

    func testFilledSelectionSurvivesTextWritesAndANSIResetsAtEachRow() {
        var canvas = TerminalCanvas(width: 8, height: 2)
        canvas.fillRow(y: 0, from: 1, to: 7, fill: .selected)
        canvas.write("CPU", x: 2, y: 0, ink: .cpu)
        canvas.write("MEM", x: 2, y: 1, ink: .memory, fill: .panel)
        let ansi = canvas.ansiLines()
        XCTAssertEqual(canvas.lines, ["  CPU   ", "  MEM   "])
        XCTAssertTrue(ansi[0].contains("38;5;81;48;5;23mCPU"))
        XCTAssertTrue(ansi[1].contains("48;5;235"))
        XCTAssertTrue(ansi.allSatisfy { $0.hasSuffix("\u{1b}[0m") })
        XCTAssertEqual(ansi.map(TerminalText.sanitize), canvas.lines)
    }

    func testBoxKeepsCornersAndFitsUnicodeTitleInsideBounds() {
        var canvas = TerminalCanvas(width: 8, height: 3)
        canvas.box(x: 0, y: 0, width: 8, height: 3, title: "界界界界")
        XCTAssertEqual(canvas.lines, ["╭ 界… ─╮", "│      │", "╰──────╯"])
        canvas.box(x: 7, y: 2, width: 4, height: 4)
        XCTAssertTrue(canvas.lines.allSatisfy { TerminalText.width($0) == 8 })
        var wide = TerminalCanvas(width: 12, height: 2)
        wide.box(x: 0, y: 0, width: 12, height: 2, title: "CPU")
        XCTAssertEqual(wide.lines.first, "╭ CPU ─────╮")
    }

    func testSparklineHasFixedScaleAndRightAlignedShortHistory() {
        XCTAssertEqual(TerminalPlot.sparkline([0, 25, 50, 100], width: 6, ceiling: 100), "  ▁▂▄█")
        XCTAssertEqual(TerminalPlot.sparkline([25, 50], width: 2, ceiling: 100), "▂▄")
        XCTAssertEqual(TerminalPlot.sparkline([25, 50], width: 2), "▄█")
        XCTAssertEqual(TerminalPlot.sparkline([], width: 4), "    ")
    }

    func testMissingInvalidAndRealZeroSamplesRemainDistinct() {
        XCTAssertEqual(TerminalPlot.sparkline([nil, .nan, .infinity, 0, 100], width: 5, ceiling: 100), "···▁█")
        XCTAssertEqual(TerminalPlot.bars([nil, 0, 50, 100], width: 4, height: 2, ceiling: 100), ["   █", "· ██"])
        XCTAssertEqual(TerminalPlot.meter(nil, width: 4), "····")
        XCTAssertEqual(TerminalPlot.meter(.nan, width: 4), "····")
        XCTAssertEqual(TerminalPlot.meter(0, width: 4), "░░░░")
    }

    func testHistoryDownsamplingPreservesPeaksAndMissingBuckets() {
        XCTAssertEqual(TerminalPlot.sparkline([0, 100, 25, 0], width: 2, ceiling: 100), "█▂")
        XCTAssertEqual(TerminalPlot.sparkline([0, 100, nil, 25, 0, 50], width: 3, ceiling: 100), "█·▄")
        XCTAssertEqual(TerminalPlot.bars([0, 100, nil, 50], width: 2, height: 2, ceiling: 100), ["█ ", "█·"])
    }

    func testFractionalBarsUseBottomUpVolumeWithoutBorders() {
        XCTAssertEqual(TerminalPlot.bars([6.25, 25, 75, 150], width: 4, height: 2, ceiling: 100), ["  ▄█", "▁▄██"])
        XCTAssertEqual(TerminalPlot.bars([100], width: 3, height: 3, ceiling: 100), ["  █", "  █", "  █"])
        XCTAssertEqual(TerminalPlot.meter(0.375, width: 4), "█▌░░")
        XCTAssertEqual(TerminalPlot.meter(2, width: 4), "████")
        XCTAssertEqual(TerminalPlot.meter(-1, width: 4), "░░░░")
    }

    func testEmptyInvalidDimensionsAndInvalidCeilingsAreSafe() {
        XCTAssertEqual(TerminalPlot.sparkline([1], width: 0), "")
        XCTAssertEqual(TerminalPlot.bars([1], width: -1, height: 2), ["", ""])
        XCTAssertEqual(TerminalPlot.bars([1], width: 2, height: 0), [])
        XCTAssertEqual(TerminalPlot.meter(1, width: -1), "")
        XCTAssertEqual(TerminalPlot.sparkline([0, 50], width: 2, ceiling: .nan), "▁█")
        XCTAssertEqual(TerminalPlot.bars([], width: 3, height: 2), ["   ", "   "])
    }
}
