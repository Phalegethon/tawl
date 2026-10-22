import XCTest
@testable import TawlCore

final class TerminalTests: XCTestCase {
    private func frame(_ time: Double, reversed: Bool = false, count: Int = 32) -> Snapshot {
        var value = Snapshot(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
        value.intervalSeconds = 2
        value.cpuPercent = 40
        value.pressure = .normal
        value.processes = (0..<count).map { index in
            ProcessSample(id: "\(index):1", pid: Int32(index + 100), name: "worker", applicationID: "app-\(index)", applicationName: "Application \(index) 長い名前 👩🏽‍💻 " + String(repeating: "é", count: 100), projectID: nil, projectName: nil, projectEvidence: nil, cpuCores: Double(reversed ? index : count-index), footprintBytes: 123_456_789, memoryDeltaBytes: 1024, diskReadBytesPerSecond: nil, diskWriteBytesPerSecond: nil)
        }
        value.totalProcessCount = count
        return value
    }

    func testInputDecoderRetainsSplitArrowsAndUTF8WithoutInterpretingAsExit() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed([27,91]), [])
        XCTAssertEqual(input.feed([66,106]), [.down,.text("j")])
        XCTAssertEqual(input.feed([0xc3]), [])
        XCTAssertEqual(input.feed([0xa9]), [.text("é")])
        XCTAssertEqual(input.feed([27]), [])
        XCTAssertEqual(input.flushEscape(), [.escape])
    }

    func testReturnCRLFIsOneKeyEvenAcrossReadBoundaries() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed([13, 10]), [.enter])
        XCTAssertEqual(input.feed([13]), [.enter])
        XCTAssertEqual(input.feed([10]), [])
        XCTAssertEqual(input.feed([13, 13]), [.enter, .enter])
        XCTAssertEqual(input.feed([105, 10]), [.text("i"), .enter])
    }

    func testApplicationKeypadEnterWorksWithoutTreatingMouseAsEnter() {
        var input = TerminalInput()
        XCTAssertEqual(input.feed([27, 79]), [])
        XCTAssertEqual(input.feed([77]), [.enter])
        XCTAssertEqual(input.feed([27, 91, 77, 32, 40, 40]), [])
    }

    func testDetailScrollingClampsAtEndAndCanImmediatelyMoveBack() {
        var state = TerminalState()
        state.scrollDetails(by: 100_000, limit: 18)
        XCTAssertEqual(state.detailScroll, 18)
        state.scrollDetails(by: -1, limit: 18)
        XCTAssertEqual(state.detailScroll, 17)
        state.scrollDetails(by: -100, limit: 18)
        XCTAssertEqual(state.detailScroll, 0)
    }

    func testHistoryExplainsUnavailableEarlierTime() {
        var state = TerminalState()
        state.accept(frame(0)); state.toggleHistory(); state.moveHistory(by: -1)
        XCTAssertTrue(state.notice.contains("No recordings"))
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 0)
    }

    func testUnicodeWidthAndClippingRespectTerminalCells() {
        XCTAssertEqual(TerminalText.width("a界e\u{301}👩🏽‍💻"), 6)
        XCTAssertEqual(TerminalText.clipped("界界界", to: 5), "界界…")
        XCTAssertEqual(TerminalText.width(TerminalText.padded("👩🏽‍💻", to: 6)), 6)
    }

    func testHostileControlSequencesCannotReachTerminal() {
        let input = "safe\u{1b}[2Jbad\u{1b}]52;c;secret\u{7}done\r\n\t\u{009b}31mend\u{202e}"
        let safe = TerminalText.sanitize(input)
        XCTAssertEqual(safe, "safebaddone   end")
        XCTAssertFalse(safe.unicodeScalars.contains { $0.value == 27 || $0.value == 0x9b || $0.value == 0x202e })
    }

    func testSelectionFollowsWorkloadIdentityAcrossResorting() {
        var state = TerminalState()
        state.accept(frame(0))
        state.moveSelection(by: 2)
        let selected = state.selectedID
        XCTAssertNotNil(selected)
        state.accept(frame(2, reversed: true))
        XCTAssertEqual(state.selectedID, selected)
        XCTAssertEqual(state.selectedWorkload?.id, selected)
    }

    func testFreezeKeepsDisplayedFrameWhileCollectingAndUnfreezeReturnsLive() {
        var state = TerminalState()
        state.accept(frame(0)); state.toggleFrozen(); state.accept(frame(2))
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 0)
        XCTAssertEqual(state.snapshots.count, 2)
        state.toggleFrozen()
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 2)
    }

    func testFrozenChartWindowSurvivesHistoryEvictionAndStaysWithinTwoMinutes() {
        var state = TerminalState()
        for time in [0.0, 60, 120, 180] { state.accept(frame(time, count: 1)) }
        state.toggleFrozen()
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [60, 120, 180])

        state.accept(frame(2_000, count: 1))
        XCTAssertEqual(state.snapshots.map(\.monotonicTime), [2_000])
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 180)
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [60, 120, 180])

        state.toggleFrozen()
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [2_000])
    }

    func testHistoricalNavigationPinsItsWindowAndReturnsToTheOriginalFrozenWindow() {
        var state = TerminalState()
        for time in [0.0, 60, 120, 180] { state.accept(frame(time, count: 1)) }
        state.toggleFrozen()
        state.toggleHistory()
        state.moveHistory(by: -1)
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [0, 60, 120])

        state.accept(frame(2_000, count: 1))
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 120)
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [0, 60, 120])

        state.toggleHistory()
        XCTAssertTrue(state.frozen)
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 180)
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [60, 120, 180])
        state.toggleFrozen()
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 2_000)
    }

    func testPinnedChartWindowBoundsPayloadAndKeepsTheNewestSamples() {
        var state = TerminalState()
        let longName = String(repeating: "x", count: 3 * 1024 * 1024)
        for time in [0.0, 2, 4] {
            var value = frame(time, count: 1)
            value.processes[0].name = longName
            state.accept(value)
        }
        state.toggleFrozen()
        // Two ~3 MiB snapshots fit the 8 MiB window budget; a third does not.
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [2, 4])
        state.accept(frame(2_000, count: 1))
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 4)
        XCTAssertEqual(state.visibleHistory.map(\.monotonicTime), [2, 4])
    }

    func testHistoryNavigationShowsActualOldMeasurementsWhileNewFramesArrive() {
        var state = TerminalState()
        state.accept(frame(0)); state.accept(frame(2)); state.accept(frame(4))
        state.toggleHistory(); state.moveHistory(by: -1)
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 2)
        state.accept(frame(6))
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 2)
        state.moveHistory(by: -1)
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 0)
        state.toggleHistory()
        XCTAssertEqual(state.visibleSnapshot?.monotonicTime, 6)
    }

    func testExitedSelectionRetainsLastDetailsRatherThanBecomingAnotherProcess() {
        var state = TerminalState()
        state.accept(frame(0, count: 2)); state.detailVisible = true
        let chosen = state.selectedID
        var next = frame(2, count: 2)
        next.processes.removeFirst()
        state.accept(next)
        XCTAssertEqual(state.selectedID, chosen)
        XCTAssertTrue(state.selectedIsMissing)
        XCTAssertEqual(state.selectedMembers.first?.id, "0:1")
    }

    func testFramesStayWithinAllSupportedTerminalBoundsAndExposeUsefulRows() {
        var state = TerminalState()
        state.accept(frame(0))
        for (width, height) in [(80,24),(100,30),(160,45)] {
            let render = TerminalRenderer.render(state, width: width, height: height)
            XCTAssertEqual(render.lines.count, height)
            XCTAssertTrue(render.lines.allSatisfy { TerminalText.width($0) <= width })
            XCTAssertGreaterThanOrEqual(render.visibleRowIDs.count, width == 80 ? 8 : 12)
            XCTAssertTrue(render.lines.joined().contains("CPU"))
            XCTAssertTrue(render.lines.joined().contains("CPU(cores)"))
        }
        let large = TerminalRenderer.render(state, width: 160, height: 45)
        XCTAssertTrue(large.lines.joined().contains("SELECTED WORKLOAD"))
    }

    func testScrollingKeepsSelectedRowVisibleAndSearchReallyFilters() {
        var state = TerminalState()
        state.accept(frame(0, count: 80)); state.moveSelection(by: 50)
        let render = TerminalRenderer.render(state, width: 100, height: 30)
        XCTAssertTrue(render.visibleRowIDs.contains(state.selectedID ?? ""))
        state.setSearch("Application 37 ")
        XCTAssertEqual(state.workloads.count, 1)
        XCTAssertTrue(state.workloads.first?.name.contains("37") == true)
        state.setSearch("does not exist")
        XCTAssertTrue(state.workloads.isEmpty)
        XCTAssertTrue(TerminalRenderer.render(state, width: 80, height: 24).lines.joined().contains("No search matches"))
    }

    func testDetailWrapsLongNamesAndMissingMetricsAreExplicit() {
        var state = TerminalState()
        var value = frame(0, count: 1)
        value.cpuPercent = nil; value.processes[0].cpuCores = nil
        value.processes[0].footprintBytes = nil
        value.processes[0].applicationName = String(repeating: "Long project name ", count: 10)
        state.accept(value); state.detailVisible = true
        let render = TerminalRenderer.render(state, width: 80, height: 24)
        XCTAssertTrue(render.lines.allSatisfy { TerminalText.width($0) <= 80 })
        XCTAssertTrue(render.lines.joined().contains("CPU —"))
        XCTAssertTrue(render.lines.joined().contains("unknown"))
        XCTAssertTrue(render.lines.joined().contains("PID"))
    }
}
