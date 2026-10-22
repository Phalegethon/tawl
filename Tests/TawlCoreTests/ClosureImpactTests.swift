import XCTest
@testable import TawlCore

final class ClosureImpactTests: XCTestCase {
    func point(_ time: Double, interval: Double? = 2, cpu: Double? = 20,
               pressure: Pressure = .normal, swap: UInt64? = 1000, rate: Double? = 10) -> Snapshot {
        var s = Snapshot(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
        s.intervalSeconds = interval; s.cpuPercent = cpu; s.pressure = pressure
        s.swapUsedBytes = swap; s.swapOutBytesPerSecond = rate
        return s
    }
    func impact(_ history: [Snapshot] = []) throws -> ClosureImpact {
        ClosureImpact(intent: try ProcessClosureTests().prepare().get(), startedAt: 100,
                      startedOn: Date(timeIntervalSince1970: 1000), history: history)
    }
    func testIrregularIntervalsUseTimeWeightsAndDeltaPercentagePoints() throws {
        var value = try impact([point(97, interval: 2, cpu: 10, rate: 20),
                                point(100, interval: 3, cpu: 30, rate: 40)])
        value.observe(point(101, interval: 1, cpu: 50, rate: 100), now: 101)
        value.observe(point(105, interval: 4, cpu: 10, rate: 0), now: 105)
        XCTAssertEqual(value.summary.before.cpu.value!, 22, accuracy: 0.0001)
        XCTAssertEqual(value.summary.before.cpu.coverageSeconds, 5)
        XCTAssertEqual(value.summary.after.cpu.value!, 18, accuracy: 0.0001)
        XCTAssertEqual(value.summary.after.cpu.coverageSeconds, 5)
        XCTAssertEqual(value.summary.cpuDeltaPercentagePoints!, -4, accuracy: 0.0001)
        XCTAssertEqual(value.summary.before.swapOut.value!, 32, accuracy: 0.0001)
        XCTAssertEqual(value.summary.after.swapOut.value!, 20, accuracy: 0.0001)
        XCTAssertEqual(value.summary.swapOutDeltaBytesPerSecond!, -12, accuracy: 0.0001)
    }
    func testCrossBoundaryPostIntervalsAreExcludedButInstantMetricsAreKept() throws {
        var value = try impact([point(100, cpu: 80, pressure: .critical, swap: 1000)])
        value.observe(point(101, interval: 2, cpu: 90, pressure: .warning, swap: 900, rate: 50), now: 101)
        XCTAssertNil(value.after[0].intervalSeconds)
        XCTAssertNil(value.after[0].cpuPercent)
        XCTAssertNil(value.after[0].swapOutBytesPerSecond)
        XCTAssertEqual(value.summary.after.cpu.coverageSeconds, 0)
        XCTAssertEqual(value.summary.after.pressure, .warning)
        XCTAssertEqual(value.summary.swapUsedDeltaBytes, -100)
    }
    func testBaselineLeftEdgeIsClippedAndPartialCoverageIsReported() throws {
        let value = try impact([point(69, cpu: 100), point(72, interval: 4, cpu: 40),
                                point(100, interval: 2, cpu: 10)])
        XCTAssertEqual(value.before.count, 2)
        XCTAssertEqual(value.before.first?.intervalSeconds, 2)
        XCTAssertEqual(value.summary.before.cpu.value!, 25, accuracy: 0.0001)
        XCTAssertEqual(value.summary.before.cpu.coverageSeconds, 4)
        XCTAssertNil(value.summary.after.cpu.value)
        XCTAssertEqual(value.summary.after.pressure, .unknown)
        XCTAssertNil(value.summary.after.swapUsedBytes)
    }
    func testMissingInvalidAndOverlappingIntervalsNeverBecomeZeroOrDoubleCoverage() throws {
        var value = try impact()
        value.observe(point(102, cpu: 20, rate: 10), now: 102)
        value.observe(point(104, cpu: nil, pressure: .unknown, swap: nil, rate: nil), now: 104)
        value.observe(point(105, interval: 3, cpu: 100, rate: 100), now: 105)
        value.observe(point(112, interval: 7, cpu: 100, rate: 100), now: 112)
        value.observe(point(114, cpu: .nan, rate: -1), now: 114)
        XCTAssertEqual(value.summary.after.cpu.value, 20)
        XCTAssertEqual(value.summary.after.cpu.coverageSeconds, 2)
        XCTAssertEqual(value.summary.after.swapOut.value, 10)
        XCTAssertEqual(value.summary.after.swapOut.coverageSeconds, 2)
        XCTAssertNil(value.after[2].intervalSeconds)
        XCTAssertNil(value.after[3].intervalSeconds)
        XCTAssertNil(value.after[4].cpuPercent)
        XCTAssertNil(value.after[4].swapOutBytesPerSecond)
    }
    func testLatestMissingInstantMetricsDoNotCarryEarlierHealthyValues() throws {
        var value = try impact([point(98), point(100, pressure: .unknown, swap: nil)])
        XCTAssertEqual(value.summary.before.pressure, .unknown)
        XCTAssertNil(value.summary.before.swapUsedBytes)
        value.observe(point(102, pressure: .normal, swap: 900), now: 102)
        value.observe(point(104, pressure: .unknown, swap: nil), now: 104)
        XCTAssertEqual(value.summary.after.pressure, .unknown)
        XCTAssertNil(value.summary.after.swapUsedBytes)
        XCTAssertNil(value.summary.swapUsedDeltaBytes)
    }
    func testInstantMetricsExpireAtBoundaryButMeasuredCoverageRemains() throws {
        var value = try impact([point(94, pressure: .normal, swap: 1000)])
        XCTAssertEqual(value.summary.before.pressure, .unknown)
        XCTAssertNil(value.summary.before.swapUsedBytes)
        XCTAssertEqual(value.summary.before.cpu.coverageSeconds, 2)
        value.observe(point(102, pressure: .warning, swap: 900), now: 102)
        value.advance(now: 108)
        XCTAssertEqual(value.summary.after.pressure, .unknown)
        XCTAssertNil(value.summary.after.swapUsedBytes)
        XCTAssertEqual(value.summary.after.cpu.coverageSeconds, 2)
    }
    func testNoSamplesCompletesAtSixtySecondsWithoutFabricatingAfter() throws {
        var value = try impact([point(100)])
        XCTAssertEqual(value.elapsed, 0); XCTAssertFalse(value.isComplete)
        value.advance(now: 159)
        XCTAssertEqual(value.elapsed, 59); XCTAssertFalse(value.isComplete)
        value.advance(now: 160)
        XCTAssertEqual(value.elapsed, 60); XCTAssertTrue(value.isComplete)
        XCTAssertTrue(value.after.isEmpty); XCTAssertNil(value.summary.cpuDeltaPercentagePoints)
        value.observe(point(160), now: 160)
        XCTAssertTrue(value.after.isEmpty)
    }
    func testPointExactlyAtSixtyAcceptedThenSummaryFreezes() throws {
        var value = try impact([point(100, swap: 1000)])
        value.observe(point(160, interval: 2, cpu: 15, pressure: .warning, swap: 1200), now: 160)
        XCTAssertEqual(value.elapsed, 60); XCTAssertTrue(value.isComplete)
        XCTAssertEqual(value.summary.after.cpu.value, 15)
        XCTAssertEqual(value.summary.swapUsedDeltaBytes, 200)
        value.observe(point(162, cpu: 99, pressure: .critical, swap: 9999), now: 162)
        value.advance(now: 1000)
        XCTAssertEqual(value.after.count, 1)
        XCTAssertEqual(value.summary.after.pressure, .warning)
        XCTAssertEqual(value.summary.swapUsedDeltaBytes, 200)
    }
    func testOutOfOrderDuplicateFutureStaleAndInvalidClockSamplesCannotCorrupt() throws {
        var value = try impact([point(1000), point(98, cpu: 10), point(98, cpu: 90), point(90), point(100, cpu: 20)])
        XCTAssertEqual(value.before.map(\.time), [98, 100])
        value.observe(point(102, cpu: 30), now: 102)
        value.observe(point(102, cpu: 90), now: 103)
        value.observe(point(101), now: 103)
        value.observe(point(110), now: 104)
        value.observe(point(104), now: 111)
        value.observe(point(112), now: .nan)
        value.observe(point(111), now: 110)
        XCTAssertEqual(value.after.map(\.time), [102])
        XCTAssertEqual(value.summary.after.cpu.value, 30)
        XCTAssertEqual(value.elapsed, 11)
    }
    func testBeyondHorizonAndNonfiniteMetricsAreAbsent() throws {
        var value = try impact([point(100, cpu: .infinity, rate: .nan)])
        XCTAssertNil(value.summary.before.cpu.value)
        XCTAssertNil(value.summary.before.swapOut.value)
        value.observe(point(161, cpu: 100), now: 161)
        XCTAssertTrue(value.isComplete); XCTAssertTrue(value.after.isEmpty)
    }
    func testPointAtActionTimeHasNoAfterIntervalAndInvalidIntervalsStayUnknown() throws {
        var value = try impact()
        value.observe(point(100, cpu: 90, pressure: .critical), now: 100)
        XCTAssertEqual(value.elapsed, 0)
        XCTAssertNil(value.summary.after.cpu.value)
        XCTAssertEqual(value.summary.after.cpu.coverageSeconds, 0)
        XCTAssertEqual(value.summary.after.pressure, .critical)
        for (time, interval) in [(102.0, 0.0), (104, -2), (106, Double.infinity), (108, Double.nan)] {
            value.observe(point(time, interval: interval), now: time)
        }
        XCTAssertNil(value.summary.after.cpu.value)
        XCTAssertNil(value.summary.after.swapOut.value)
        XCTAssertEqual(value.summary.after.cpu.coverageSeconds, 0)
    }
    func testRetainsOnlyBoundedCompactPointsAndFrozenBaseline() throws {
        var history = (0...300).map { point(70 + Double($0)/10, interval: 0.1) }
        history[history.count - 1].processes = Array(repeating: ProcessClosureTests().process(), count: 1000)
        var value = try impact(history)
        let beforeTimes = value.before.map(\.time)
        XCTAssertLessThanOrEqual(value.before.count, 121)
        for i in 1...600 { value.observe(point(100 + Double(i)/10, interval: 0.1), now: 100 + Double(i)/10) }
        XCTAssertLessThanOrEqual(value.after.count, 241)
        XCTAssertEqual(value.before.map(\.time), beforeTimes)
        XCTAssertLessThanOrEqual(value.summary.after.cpu.coverageSeconds, 24.1 + 0.0001)
        XCTAssertTrue(value.isComplete)
        XCTAssertEqual(value.intent.processID, "42:100")
        XCTAssertEqual(value.startedOn, Date(timeIntervalSince1970: 1000))
    }
    func testOverflowingStockDifferenceIsUnknownAndZeroRemainsKnown() throws {
        var value = try impact([point(100, swap: 0)])
        value.observe(point(102, swap: UInt64.max), now: 102)
        XCTAssertNil(value.summary.swapUsedDeltaBytes)
        var zero = try impact([point(100, cpu: 0, swap: 0, rate: 0)])
        zero.observe(point(102, cpu: 0, swap: 0, rate: 0), now: 102)
        XCTAssertEqual(zero.summary.cpuDeltaPercentagePoints, 0)
        XCTAssertEqual(zero.summary.swapUsedDeltaBytes, 0)
        XCTAssertEqual(zero.summary.swapOutDeltaBytesPerSecond, 0)
    }
}
