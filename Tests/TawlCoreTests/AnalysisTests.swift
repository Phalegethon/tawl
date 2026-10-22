import XCTest
@testable import TawlCore

final class AnalysisTests: XCTestCase {
    func frame(_ t: Double, pressure: Pressure = .normal, cpu: Double = 5) -> Snapshot {
        var s = Snapshot(timestamp: Date(timeIntervalSince1970: t), monotonicTime: t)
        s.pressure = pressure; s.cpuPercent = cpu; s.intervalSeconds = 2
        s.swapUsedBytes = 20_000_000_000
        return s
    }
    func testStableSwapDoesNotBecomeMemoryPressure() {
        let findings = analyze([frame(0), frame(60)])
        XCTAssertFalse(findings.contains { $0.code == "memory-pressure" })
    }
    func testCurrentPressureIsObservationNotLeakDiagnosis() {
        let findings = analyze([frame(0, pressure: .warning)])
        XCTAssertTrue(findings.contains { $0.code == "memory-pressure" && $0.severity == "warning" })
        XCTAssertFalse(findings.contains { $0.detail.lowercased().contains("sızıntı var") })
    }
    func testShortOrGappedCPUHistoryCannotProveSustainedLoad() {
        XCTAssertFalse(analyze([frame(0, cpu: 99), frame(2, cpu: 99)]).contains { $0.code == "sustained-cpu" })
        XCTAssertFalse(analyze([frame(0, cpu: 99), frame(60, cpu: 99)]).contains { $0.code == "sustained-cpu" })
        let continuous = stride(from: 0.0, through: 60, by: 2).map { frame($0, cpu: 95) }
        XCTAssertTrue(analyze(continuous).contains { $0.code == "sustained-cpu" })
    }
    func testSustainedCPUStartsAfterThirtySecondsEvenWithEarlierIdle() {
        let samples = stride(from: 0.0, through: 60, by: 2).map { frame($0, cpu: $0 < 20 ? 5 : 95) }
        let finding = analyze(samples).first { $0.code == "sustained-cpu" }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.start, Date(timeIntervalSince1970: 20))
    }
    func testCPUFindingUsesCPUConsumersEvenDuringMemoryPressure() {
        var samples = stride(from: 0.0, through: 30, by: 2).map { frame($0, pressure: .warning, cpu: 95) }
        for index in samples.indices {
            samples[index].processes = (1...3).map { n in
                ProcessSample(id: "ram\(n)", pid: Int32(n), name: "RAM", applicationID: "ram\(n)", applicationName: "RAM", cpuCores: 0.01, footprintBytes: 1_000_000)
            } + [ProcessSample(id: "cpu", pid: 5, name: "CPUWorker", applicationID: "cpu", applicationName: "CPUWorker", cpuCores: 8, footprintBytes: 100)]
        }
        let finding = analyze(samples).first { $0.code == "sustained-cpu" }
        XCTAssertEqual(finding?.relatedWorkloadIDs.first, "cpu")
    }
    func testTerminalControlCharactersAreRemoved() {
        let safe = cleanText("node\u{1b}]52;c;secret\u{7}\n\tfoo\u{1b}[31mred\u{1b}[0m")
        XCTAssertFalse(safe.contains("\u{1b}")); XCTAssertFalse(safe.contains("\n"))
        XCTAssertFalse(safe.contains("secret")); XCTAssertTrue(safe.contains("node"))
    }
}
