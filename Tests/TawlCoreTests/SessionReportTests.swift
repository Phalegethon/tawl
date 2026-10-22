import XCTest
@testable import TawlCore

final class SessionReportTests: XCTestCase {
    private func frame(_ time: Double, pressure: Pressure = .normal, cpu: Double = 5) -> Snapshot {
        var sample = Snapshot(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
        sample.pressure = pressure
        sample.cpuPercent = cpu
        sample.intervalSeconds = 2
        return sample
    }

    func testReportWindowUsesMonotonicTimeAcrossBackwardWallClockJump() {
        var first = frame(0)
        first.timestamp = Date(timeIntervalSince1970: 100)
        var second = frame(10)
        second.timestamp = Date(timeIntervalSince1970: 50)
        var third = frame(20)
        third.timestamp = Date(timeIntervalSince1970: 60)
        let samples = [first, second, third]
        XCTAssertEqual(reportWindow(samples, lastSeconds: 15).map(\.monotonicTime), [10, 20])
        XCTAssertEqual(reportWindow(samples, lastSeconds: nil).map(\.monotonicTime), [0, 10, 20])
        XCTAssertEqual(reportWindow(samples, lastSeconds: 0).map(\.monotonicTime), [20])
        XCTAssertTrue(reportWindow(samples, lastSeconds: -1).isEmpty)
        XCTAssertTrue(reportWindow(samples, lastSeconds: .nan).isEmpty)
    }

    func testEarlierPressureAndSwapEpisodesSurviveRecoveryWithoutContradictorySummary() {
        var first = frame(2, pressure: .warning)
        first.swapOutBytesPerSecond = 100
        var second = frame(4, pressure: .warning)
        second.swapOutBytesPerSecond = 200
        let findings = analyzeSession([frame(0), first, second, frame(6)])
        for code in ["memory-pressure", "active-swap"] {
            let events = findings.filter { $0.code == code }
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.start.timeIntervalSince1970, 2)
            XCTAssertEqual(events.first?.end.timeIntervalSince1970, 4)
        }
        XCTAssertFalse(findings.contains { $0.code == "no-evidence" })
    }

    func testRecoverySeverityChangesAndSamplingGapsSplitEpisodes() {
        let recovery = analyzeSession([frame(0, pressure: .warning), frame(2), frame(4, pressure: .warning)])
        XCTAssertEqual(recovery.filter { $0.code == "memory-pressure" }.count, 2)
        let severity = analyzeSession([frame(0, pressure: .warning), frame(2, pressure: .critical)])
        XCTAssertEqual(severity.filter { $0.code == "memory-pressure" }.map(\.severity), ["warning", "critical"])
        let gap = analyzeSession([frame(0, pressure: .warning), frame(10, pressure: .warning)])
        XCTAssertEqual(gap.filter { $0.code == "memory-pressure" }.count, 2)
    }

    func testSustainedCPUIsPreservedAfterRecoveryAndCoalescesConsecutiveEvidence() {
        let high = stride(from: 0.0, through: 40, by: 2).map { frame($0, cpu: 95) }
        let episodes = analyzeSession(high + [frame(42)]).filter { $0.code == "sustained-cpu" }
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.start.timeIntervalSince1970, 0)
        XCTAssertEqual(episodes.first?.end.timeIntervalSince1970, 40)
    }

    func testHighFrequencySamplingKeepsEnoughDurationForCPUThreshold() {
        let high = (0...350).map { frame(Double($0) / 10, cpu: 95) }
        XCTAssertEqual(analyzeSession(high + [frame(35.1)]).filter { $0.code == "sustained-cpu" }.count, 1)
    }

    func testCPUThresholdNeverBridgesACollectionGap() {
        let first = stride(from: 0.0, through: 28, by: 2).map { frame($0, cpu: 95) }
        let second = stride(from: 40.0, through: 68, by: 2).map { frame($0, cpu: 95) }
        XCTAssertFalse(analyzeSession(first + second).contains { $0.code == "sustained-cpu" })
        let longFirst = stride(from: 0.0, through: 40, by: 2).map { frame($0, cpu: 95) }
        let longSecond = stride(from: 100.0, through: 140, by: 2).map { frame($0, cpu: 95) }
        XCTAssertEqual(analyzeSession(longFirst + longSecond).filter { $0.code == "sustained-cpu" }.count, 2)
    }

    func testThirtySecondsOfHighCPUAfterIdleProducesAnEpisode() {
        let high = stride(from: 3.0, through: 31, by: 2).map { frame($0, cpu: 95) }
        let samples = [frame(0)] + high
        XCTAssertFalse(analyzeSession(samples).contains { $0.code == "sustained-cpu" })
        let events = analyzeSession(samples + [frame(33, cpu: 95)]).filter { $0.code == "sustained-cpu" }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.start.timeIntervalSince1970, 3)
        XCTAssertEqual(events.first?.end.timeIntervalSince1970, 33)
    }

    func testMissingIntervalResetsTheHighCPURun() {
        var samples = stride(from: 0.0, through: 58, by: 2).map { frame($0, cpu: 95) }
        samples[15].intervalSeconds = nil
        XCTAssertFalse(analyzeSession(samples).contains { $0.code == "sustained-cpu" })
        let events = analyzeSession(samples + [frame(60, cpu: 95)]).filter { $0.code == "sustained-cpu" }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.start.timeIntervalSince1970, 30)
    }

    func testDenseRecordingDoesNotRescanOrCopyItsGrowingHistory() {
        let samples = (0..<20_000).map { frame(Double($0) * 0.0001) }
        let started = ProcessInfo.processInfo.systemUptime
        let findings = analyzeSession(samples)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertEqual(findings.map(\.code), ["no-evidence"])
        XCTAssertLessThan(elapsed, 5, "A 20,000-sample recording should use one forward pass")
    }

    func testLatestInformationalCoverageAppearsOnce() {
        var first = frame(0)
        first.unreadableProcessCount = 1
        var second = frame(2)
        second.unreadableProcessCount = 3
        let coverage = analyzeSession([first, second]).filter { $0.code == "partial-coverage" }
        XCTAssertEqual(coverage.count, 1)
        XCTAssertEqual(coverage.first?.start.timeIntervalSince1970, 2)
        XCTAssertEqual(coverage.first?.end.timeIntervalSince1970, 2)
        XCTAssertTrue(analyzeSession([]).isEmpty)
    }

    func testEpisodeWorkloadUnionIsBoundedAndRetainsRecentCandidates() {
        let samples = (0..<20).map { index -> Snapshot in
            var sample = frame(Double(index * 2), pressure: .warning)
            sample.processes = [ProcessSample(id: "\(index):0", pid: Int32(index + 1), name: "app",
                applicationID: "app-\(index)", applicationName: "app", projectID: nil, projectName: nil,
                projectEvidence: nil, cpuCores: 1, footprintBytes: 1_000, memoryDeltaBytes: nil,
                diskReadBytesPerSecond: nil, diskWriteBytesPerSecond: nil)]
            return sample
        }
        let episode = analyzeSession(samples).first { $0.code == "memory-pressure" }
        XCTAssertEqual(episode?.relatedWorkloadIDs.count, 12)
        let latestID = groupProcesses(samples.last!, by: .application).first!.id
        XCTAssertTrue(episode?.relatedWorkloadIDs.contains(latestID) ?? false)
    }
}
