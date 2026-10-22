import XCTest
@testable import TawlCore

final class ReducerTests: XCTestCase {
    func reading(_ time: Double, busy: UInt64, total: UInt64, cpu: UInt64, start: UInt64 = 123) -> RawReading {
        var r = RawReading(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
        r.cpuTicks = CPUTicks(busy: busy, total: total)
        r.swapOutBytes = UInt64(time * 100)
        r.processes = [RawProcess(pid: 42, startedAt: start, name: "worker", cpuNanoseconds: cpu, footprintBytes: 1000)]
        return r
    }
    func testIntervalsAreMeasuredRatherThanCumulative() {
        let reducer = SnapshotReducer()
        let first = reducer.reduce(reading(10, busy: 100, total: 200, cpu: 5_000_000_000))
        XCTAssertNil(first.cpuPercent)
        let next = reducer.reduce(reading(12, busy: 150, total: 400, cpu: 8_000_000_000))
        XCTAssertEqual(next.cpuPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(next.processes.first?.cpuCores ?? -1, 1.5, accuracy: 0.001)
        XCTAssertEqual(next.swapOutBytesPerSecond ?? -1, 100, accuracy: 0.001)
    }
    func testReusedPIDDoesNotInheritPreviousProcessCounters() {
        let reducer = SnapshotReducer()
        _ = reducer.reduce(reading(10, busy: 100, total: 200, cpu: 5_000_000_000))
        let next = reducer.reduce(reading(12, busy: 150, total: 400, cpu: 8_000_000_000, start: 999))
        XCTAssertEqual(next.processes.count, 1)
        XCTAssertNil(next.processes.first?.cpuCores)
    }
    func testResetAndSleepGapRemainUnknown() {
        let reducer = SnapshotReducer()
        _ = reducer.reduce(reading(10, busy: 100, total: 200, cpu: 5_000_000_000))
        let reset = reducer.reduce(reading(12, busy: 1, total: 4, cpu: 1))
        XCTAssertNil(reset.cpuPercent)
        XCTAssertNil(reset.processes.first?.cpuCores)
        let gap = reducer.reduce(reading(100, busy: 50, total: 100, cpu: 10))
        XCTAssertNil(gap.cpuPercent)
        XCTAssertFalse(gap.limitations.isEmpty)
    }
}
