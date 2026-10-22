import XCTest
import Darwin
import CTawl
@testable import TawlCore

final class HardwareTelemetryTests: XCTestCase {
    private func reading(_ time: Double, _ cores: [RawCPUCore]?) -> RawReading {
        var raw = RawReading(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
        raw.logicalCPUCount = cores?.count ?? 0
        raw.cpuCores = cores
        return raw
    }
    private func core(_ id: Int, _ user: UInt32, _ idle: UInt32, kind: CPUCoreKind = .efficiency) -> RawCPUCore {
        RawCPUCore(id: id, kind: kind, user: user, system: 0, idle: idle)
    }
    private func core(_ user: UInt32, _ idle: UInt32, kind: CPUCoreKind = .efficiency) -> RawCPUCore {
        core(0, user, idle, kind: kind)
    }

    func testPerCoreRatesUseSeparateCountersAndStableIDs() throws {
        let reducer = SnapshotReducer()
        let first = reducer.reduce(reading(10, [core(0, 100, 100), core(1, 100, 100, kind: .performance)]))
        XCTAssertEqual(first.cpuCores?.count, 2)
        XCTAssertTrue(try XCTUnwrap(first.cpuCores).allSatisfy { $0.utilizationPercent == nil })
        let second = reducer.reduce(reading(12, [core(1, 100, 200, kind: .performance), core(0, 175, 125)]))
        let cores = try XCTUnwrap(second.cpuCores)
        XCTAssertEqual(cores.map(\.id), [0, 1])
        XCTAssertEqual(cores.map(\.kind), [.efficiency, .performance])
        XCTAssertEqual(try XCTUnwrap(cores[0].utilizationPercent), 75, accuracy: 0.0001)
        XCTAssertEqual(cores[1].utilizationPercent, 0)
    }

    func testSystemAndNiceTicksAreIncludedWithoutOverflow() throws {
        let reducer = SnapshotReducer()
        _ = reducer.reduce(reading(1, [RawCPUCore(id: 7, user: 0, system: 0, nice: 0, idle: 0)]))
        let raw = RawCPUCore(id: 7, user: 10, system: 20, nice: 30, idle: 40)
        XCTAssertEqual(reducer.reduce(reading(3, [raw])).cpuCores?.first?.utilizationPercent, 60)
        let huge = RawCPUCore(id: 7, user: .max, system: .max, nice: .max, idle: .max)
        let value = try XCTUnwrap(reducer.reduce(reading(5, [huge])).cpuCores?.first?.utilizationPercent)
        XCTAssertTrue(value.isFinite)
        XCTAssertTrue((0...100).contains(value))
    }

    func testMissingAndPausedSamplesResetCoreBaselines() throws {
        let reducer = SnapshotReducer()
        _ = reducer.reduce(reading(1, [core(10, 10)]))
        XCTAssertNil(reducer.reduce(reading(3, nil)).cpuCores)
        XCTAssertNil(reducer.reduce(reading(5, [core(20, 20)])).cpuCores?.first?.utilizationPercent)
        XCTAssertEqual(reducer.reduce(reading(7, [core(30, 30)])).cpuCores?.first?.utilizationPercent, 50)
        XCTAssertNil(reducer.reduce(reading(24, [core(40, 40)])).cpuCores?.first?.utilizationPercent)
        XCTAssertEqual(reducer.reduce(reading(26, [core(50, 50)])).cpuCores?.first?.utilizationPercent, 50)
    }

    func testZeroTicksCounterResetWrapAndTopologyChangesStayUnknown() throws {
        let reducer = SnapshotReducer()
        _ = reducer.reduce(reading(1, [core(100, 100)]))
        XCTAssertNil(reducer.reduce(reading(3, [core(100, 100)])).cpuCores?.first?.utilizationPercent)
        XCTAssertNil(reducer.reduce(reading(5, [core(1, 101)])).cpuCores?.first?.utilizationPercent)
        _ = reducer.reduce(reading(7, [core(.max, 102)]))
        XCTAssertNil(reducer.reduce(reading(9, [core(2, 103)])).cpuCores?.first?.utilizationPercent)
        XCTAssertNil(reducer.reduce(reading(11, [core(3, 104, kind: .performance)])).cpuCores?.first?.utilizationPercent)
        let changed = reducer.reduce(reading(13, [core(4, 105, kind: .performance), core(1, 10, 10)]))
        XCTAssertTrue(try XCTUnwrap(changed.cpuCores).allSatisfy { $0.utilizationPercent == nil })
    }

    func testDuplicateAndOutOfRangeRawCoreIDsDoNotCrashReducer() {
        let reducer = SnapshotReducer()
        XCTAssertNil(reducer.reduce(reading(1, [core(0, 1, 1), core(0, 1, 1)])).cpuCores)
        XCTAssertNil(reducer.reduce(reading(3, [core(Int.max, 1, 1)])).cpuCores)
        XCTAssertNil(reducer.reduce(reading(5, [core(-1, 1, 1)])).cpuCores)
    }

    func testGPUIsDeviceSnapshotAndMissingDataIsNotZero() throws {
        var raw = reading(1, nil)
        raw.gpus = [GPUSample(id: "device:1", name: "GPU", coreCount: 38, utilizationPercent: 0),
                    GPUSample(id: "device:2", name: "GPU", utilizationPercent: nil),
                    GPUSample(id: "device:3", name: "GPU", utilizationPercent: .nan,
                              rendererUtilizationPercent: 101, tilerUtilizationPercent: -1)]
        let reducer = SnapshotReducer()
        let gpus = try XCTUnwrap(reducer.reduce(raw).gpus)
        XCTAssertEqual(gpus[0].utilizationPercent, 0)
        XCTAssertEqual(gpus[0].coreCount, 38)
        XCTAssertNil(gpus[1].utilizationPercent)
        XCTAssertNil(gpus[2].utilizationPercent)
        XCTAssertNil(gpus[2].rendererUtilizationPercent)
        XCTAssertNil(gpus[2].tilerUtilizationPercent)
        XCTAssertNil(reducer.reduce(reading(3, nil)).gpus, "A failed GPU read must not reuse a stale percentage")
    }

    func testHardwareRoundTripAndOldRecordsWithoutHardwareFields() throws {
        var snapshot = Snapshot(timestamp: Date(timeIntervalSince1970: 10), monotonicTime: 10)
        snapshot.cpuCores = [CPUCoreSample(id: 0, kind: .efficiency, utilizationPercent: 25),
                             CPUCoreSample(id: 1, kind: .unknown, utilizationPercent: nil)]
        snapshot.gpus = [GPUSample(id: "ioreg:123", name: "Apple M2 Max", coreCount: 38, utilizationPercent: 42)]
        let decoded = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.cpuCores, snapshot.cpuCores)
        XCTAssertEqual(decoded.gpus, snapshot.gpus)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "cpuCores"); object.removeValue(forKey: "gpus")
        let old = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.cpuCores); XCTAssertNil(old.gpus)
        try withRecord(snapshot) { url in
            let recorded = try XCTUnwrap(RecordingReader.read(url: url).snapshots.first)
            XCTAssertEqual(recorded.cpuCores, snapshot.cpuCores)
            XCTAssertEqual(recorded.gpus, snapshot.gpus)
        }
    }

    func testRecordingReaderRejectsMalformedHardwareValues() throws {
        let baseline = Snapshot(timestamp: Date(timeIntervalSince1970: 1), monotonicTime: 1)
        var bad: [Snapshot] = []
        for cores in [
            [CPUCoreSample(id: -1, kind: .unknown, utilizationPercent: 0)],
            [CPUCoreSample(id: Int.max, kind: .unknown, utilizationPercent: 0)],
            [CPUCoreSample(id: 0, kind: .unknown, utilizationPercent: 100.1)],
            [CPUCoreSample(id: 0, kind: .unknown, utilizationPercent: -1)],
            [CPUCoreSample(id: 0, kind: .unknown, utilizationPercent: nil), CPUCoreSample(id: 0, kind: .unknown, utilizationPercent: nil)],
            (0...HardwareLimits.cpuCount).map { CPUCoreSample(id: $0, kind: .unknown, utilizationPercent: nil) }
        ] { var snapshot = baseline; snapshot.cpuCores = cores; bad.append(snapshot) }
        for gpus in [
            [GPUSample(id: "x", name: "GPU", utilizationPercent: 101)],
            [GPUSample(id: "x", name: "GPU", utilizationPercent: 0, rendererUtilizationPercent: -1)],
            [GPUSample(id: "x", name: "GPU", coreCount: Int.max, utilizationPercent: 0)],
            [GPUSample(id: "x", name: "GPU", coreCount: 0, utilizationPercent: 0)],
            [GPUSample(id: "", name: "GPU", utilizationPercent: nil)],
            [GPUSample(id: "x", name: String(repeating: "x", count: 1025), utilizationPercent: nil)],
            [GPUSample(id: "x", name: "GPU", utilizationPercent: nil), GPUSample(id: "x", name: "GPU", utilizationPercent: nil)],
            (0...HardwareLimits.gpuCount).map { GPUSample(id: "\($0)", name: "GPU", utilizationPercent: nil) }
        ] { var snapshot = baseline; snapshot.gpus = gpus; bad.append(snapshot) }
        for snapshot in bad {
            try withRecord(snapshot) { url in XCTAssertThrowsError(try RecordingReader.read(url: url)) }
        }
    }

    func testLiveNativeCPUIdentityAndGPUCapabilityAreBounded() throws {
        let pointer = try XCTUnwrap(nb_collect_hardware())
        defer { nb_free_hardware(pointer) }
        let reading = pointer.pointee
        XCTAssertNotEqual(reading.valid & UInt32(NB_HARDWARE_CPU_VALID), 0)
        XCTAssertGreaterThan(reading.cpu_count, 0)
        XCTAssertLessThanOrEqual(reading.cpu_count, UInt32(NB_MAX_CPU_COUNT))
        let cores = try XCTUnwrap(reading.cpus)
        let ids = (0..<Int(reading.cpu_count)).map { cores[$0].id }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0 >= 0 && $0 <= NB_MAX_CPU_ID })
        for index in ids.indices {
            XCTAssertTrue([NB_CPU_KIND_UNKNOWN, NB_CPU_KIND_EFFICIENCY, NB_CPU_KIND_PERFORMANCE].contains(Int(cores[index].kind)))
        }
        XCTAssertLessThanOrEqual(reading.gpu_count, UInt32(NB_MAX_GPU_COUNT))
        if let gpus = reading.gpus {
            for index in 0..<Int(reading.gpu_count) {
                if gpus[index].valid & UInt32(NB_GPU_DEVICE_VALID) != 0 {
                    XCTAssertTrue(gpus[index].utilization_percent.isFinite)
                    XCTAssertTrue((0...100).contains(gpus[index].utilization_percent))
                }
            }
        }
    }

    private func withRecord(_ snapshot: Snapshot, perform: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-hardware-\(UUID().uuidString).ndjson")
        defer { try? FileManager.default.removeItem(at: url) }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
        var data = Data("{\"type\":\"header\",\"format\":\"tawl\",\"version\":1}\n".utf8)
        data.append(try JSONSerialization.data(withJSONObject: ["type": "snapshot", "snapshot": object]))
        data.append(10)
        try data.write(to: url, options: .withoutOverwriting)
        try perform(url)
    }
}
