import XCTest
import Foundation
@testable import TawlCore

final class RecordingTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("session.tawl") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func sample(_ time: Double, name: String = "worker") -> Snapshot {
        var value = Snapshot(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
        value.intervalSeconds = 2
        value.cpuPercent = 25
        value.logicalCPUCount = 8
        value.memoryTotalBytes = 16_000_000_000
        value.processes = [ProcessSample(id: "42:10", pid: 42, name: name, applicationID: "app",
            applicationName: "Worker", projectID: nil, projectName: nil, projectEvidence: nil,
            cpuCores: nil, footprintBytes: nil, memoryDeltaBytes: nil,
            diskReadBytesPerSecond: nil, diskWriteBytesPerSecond: nil)]
        value.limitations = ["Measurement permission denied"]
        return value
    }

    private var header: String { "{\"type\":\"header\",\"format\":\"tawl\",\"version\":1}\n" }

    // Literal pre-rename v1 schema, independent of the current writer/encoder. The
    // older sample intentionally has no CPU/GPU hardware or closure-review fields.
    private var legacyRecording: String {
        """
        {"type":"header","format":"nabiz","version":1}
        {"type":"snapshot","snapshot":{"timestamp":10,"monotonicTime":10,"intervalSeconds":2,"cpuPercent":25,"logicalCPUCount":8,"memoryTotalBytes":16000000000,"pressure":"warning","compressedBytes":1048576,"swapUsedBytes":2097152,"swapOutBytesPerSecond":4096,"totalProcessCount":2,"unreadableProcessCount":1,"processes":[{"id":"42:10","pid":42,"name":"worker","applicationID":"app","applicationName":"Worker","footprintBytes":524288,"memoryDeltaBytes":1024}],"limitations":["Measurement permission denied"]}}
        {"type":"marker","marker":{"timestamp":11,"label":"Slowdown observed"}}
        {"type":"snapshot","snapshot":{"timestamp":12,"monotonicTime":12,"intervalSeconds":2,"cpuPercent":20,"logicalCPUCount":8,"memoryTotalBytes":16000000000,"pressure":"normal","swapUsedBytes":2097152,"swapOutBytesPerSecond":0,"totalProcessCount":2,"unreadableProcessCount":1,"processes":[{"id":"42:10","pid":42,"name":"worker","applicationID":"app","applicationName":"Worker","cpuCores":0.5,"footprintBytes":524288,"memoryDeltaBytes":0}],"limitations":[]}}
        """ + "\n"
    }
    private func snapshotLine(_ snapshot: Snapshot) throws -> String {
        let payload = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        return "{\"type\":\"snapshot\",\"snapshot\":\(payload)}\n"
    }
    private func write(_ contents: String) throws { try Data(contents.utf8).write(to: file) }

    func testLegacyRecordingAndTawlHeaderDecodeIdenticalSamplesAndMarkers() throws {
        let legacyFile = directory.appendingPathComponent("legacy.nabiz")
        try Data(legacyRecording.utf8).write(to: legacyFile)
        try write(legacyRecording.replacingOccurrences(of: "\"format\":\"nabiz\"", with: "\"format\":\"tawl\""))
        let legacy = try RecordingReader.read(url: legacyFile)
        let current = try RecordingReader.read(url: file)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(legacy.snapshots), try encoder.encode(current.snapshots))
        XCTAssertEqual(try encoder.encode(legacy.markers), try encoder.encode(current.markers))
        XCTAssertEqual(current.snapshots.map(\.monotonicTime), [10, 12])
        XCTAssertEqual(current.snapshots.map(\.cpuPercent), [25, 20])
        XCTAssertEqual(current.snapshots.map(\.pressure), [.warning, .normal])
        XCTAssertEqual(current.snapshots.map(\.swapOutBytesPerSecond), [4096, 0])
        let first = try XCTUnwrap(current.snapshots.first)
        XCTAssertEqual(first.timestamp.timeIntervalSinceReferenceDate, 10)
        XCTAssertEqual(first.processes.first?.id, "42:10")
        XCTAssertEqual(first.processes.first?.applicationName, "Worker")
        XCTAssertEqual(first.processes.first?.footprintBytes, 524288)
        XCTAssertEqual(first.limitations, ["Measurement permission denied"])
        XCTAssertNil(first.cpuCores)
        XCTAssertNil(first.gpus)
        XCTAssertNil(first.processes.first?.cpuCores)
        XCTAssertNil(first.processes.first?.canReviewClosure)
        XCTAssertEqual(current.markers.map(\.label), ["Slowdown observed"])
        XCTAssertEqual(current.markers.first?.timestamp.timeIntervalSinceReferenceDate, 11)
        XCTAssertTrue(legacy.warnings.isEmpty)
        XCTAssertTrue(current.warnings.isEmpty)
    }

    func testWriterEmitsTawlVersionOneHeader() throws {
        let writer = try RecordingWriter(url: file)
        try writer.close()
        let contents = try Data(contentsOf: file)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any])
        XCTAssertEqual(value["type"] as? String, "header")
        XCTAssertEqual(value["format"] as? String, "tawl")
        XCTAssertEqual(value["version"] as? Int, 1)
    }

    func testRoundTripPreservesSamplesMarkersAndUnavailableMetrics() throws {
        let writer = try RecordingWriter(url: file)
        try writer.append(sample(10))
        try writer.appendMarker(EventMarker(timestamp: Date(timeIntervalSince1970: 11), label: "Slowdown observed"))
        try writer.append(sample(12))
        try writer.close()
        let recording = try RecordingReader.read(url: file)
        XCTAssertEqual(recording.snapshots.map(\.monotonicTime), [10, 12])
        let first = try XCTUnwrap(recording.snapshots.first)
        XCTAssertEqual(first.cpuPercent, 25)
        XCTAssertEqual(first.timestamp.timeIntervalSince1970, 10)
        XCTAssertNil(first.processes.first?.cpuCores)
        XCTAssertNil(first.processes.first?.footprintBytes)
        XCTAssertEqual(first.limitations, ["Measurement permission denied"])
        XCTAssertEqual(recording.markers.map(\.label), ["Slowdown observed"])
        XCTAssertTrue(recording.warnings.isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testChangingLanguageDoesNotTranslateRecordedNamesLabelsOrEvidence() throws {
        let label = try XCTUnwrap(TurkishCore.strings["Slowdown marker"])
        let evidence = try XCTUnwrap(TurkishCore.strings["System CPU counters unavailable."])
        try L10n.withLanguage(.turkish) {
            var value = sample(10, name: "Memory pressure")
            value.limitations = [evidence]
            let writer = try RecordingWriter(url: file)
            try writer.append(value)
            try writer.appendMarker(EventMarker(timestamp: Date(timeIntervalSince1970: 11), label: label))
            try writer.close()
        }
        let recording = try L10n.withLanguage(.english) { try RecordingReader.read(url: file) }
        XCTAssertEqual(recording.snapshots.first?.processes.first?.name, "Memory pressure")
        XCTAssertEqual(recording.snapshots.first?.limitations, [evidence])
        XCTAssertEqual(recording.markers.first?.label, label)
        XCTAssertEqual(recording.snapshots.first?.processes.first?.id, "42:10")
    }

    func testExistingFileIsNeverOverwritten() throws {
        try write("important existing contents")
        XCTAssertThrowsError(try RecordingWriter(url: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "important existing contents")
    }

    func testSymbolicLinkIsNeverFollowed() throws {
        let target = directory.appendingPathComponent("target")
        try Data("preserve".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertThrowsError(try RecordingWriter(url: file))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "preserve")
    }

    func testHeaderOnlyRecordingIsValid() throws {
        try write(header)
        let recording = try RecordingReader.read(url: file)
        XCTAssertTrue(recording.snapshots.isEmpty)
        XCTAssertTrue(recording.warnings.isEmpty)
    }

    func testUnsupportedFormatOrVersionIsRejected() throws {
        for format in ["other", "TAWL", "Nabiz", "tawl ", "", "tawl-v1"] {
            try write("{\"type\":\"header\",\"format\":\"\(format)\",\"version\":1}\n")
            XCTAssertThrowsError(try RecordingReader.read(url: file)) { error in
                guard case RecordingError.invalidFormat = error else {
                    return XCTFail("Expected invalidFormat for \(format), received \(error)")
                }
            }
        }
        for format in ["nabiz", "tawl"] {
            try write("{\"type\":\"header\",\"format\":\"\(format)\",\"version\":2}\n")
            XCTAssertThrowsError(try RecordingReader.read(url: file)) { error in
                guard case RecordingError.unsupportedVersion(2) = error else {
                    return XCTFail("Expected unsupportedVersion for \(format), received \(error)")
                }
            }
        }
        for value in ["", "{\"type\":\"header\",\"format\":\"tawl\"}\n",
                      "{\"type\":\"header\",\"format\":\"tawl\",\"version\":1,\"marker\":{\"timestamp\":10,\"label\":\"invalid\"}}\n"] {
            try write(value)
            XCTAssertThrowsError(try RecordingReader.read(url: file))
        }
    }

    func testTruncatedFinalRowRetainsCompleteSamplesAndWarns() throws {
        try write(header + snapshotLine(sample(10)) + "{\"type\":\"snapshot\",\"snapshot\":{")
        let recording = try RecordingReader.read(url: file)
        XCTAssertEqual(recording.snapshots.map(\.monotonicTime), [10])
        XCTAssertEqual(recording.warnings.count, 1)
    }

    func testCompleteFinalRowWithoutNewlineIsAccepted() throws {
        try write(header + snapshotLine(sample(10)).dropLast())
        let recording = try RecordingReader.read(url: file)
        XCTAssertEqual(recording.snapshots.count, 1)
        XCTAssertTrue(recording.warnings.isEmpty)
    }

    func testInteriorCorruptionAndUnknownRowTypesAreRejected() throws {
        for bad in ["{broken}\n", "{\"type\":\"alien\"}\n", "\n", header] {
            try write(header + bad + snapshotLine(sample(10)))
            XCTAssertThrowsError(try RecordingReader.read(url: file))
        }
    }

    func testInvalidSampleNumbersAreRejected() throws {
        for invalid in [-1.0, Double.infinity, Double.nan] {
            var snapshot = sample(10)
            snapshot.cpuPercent = invalid
            let output = directory.appendingPathComponent(UUID().uuidString)
            let writer = try RecordingWriter(url: output)
            XCTAssertThrowsError(try writer.append(snapshot))
            try writer.close()
        }
        let base = try snapshotLine(sample(10))
        for broken in [base.replacingOccurrences(of: "\"cpuPercent\":25", with: "\"cpuPercent\":1e999"),
                       base.replacingOccurrences(of: "\"monotonicTime\":10", with: "\"monotonicTime\":-1"),
                       base.replacingOccurrences(of: "\"intervalSeconds\":2", with: "\"intervalSeconds\":0")] {
            try write(header + broken)
            XCTAssertThrowsError(try RecordingReader.read(url: file))
        }
    }

    func testInvalidCompleteFinalRowIsRejectedEvenWithoutNewline() throws {
        for row in ["{\"type\":\"alien\"}", "{broken}", "{\"type\":invalid"] {
            try write(header + row)
            XCTAssertThrowsError(try RecordingReader.read(url: file))
        }
    }

    func testNonFiniteTimesAndNegativeRatesAreRejected() throws {
        let writer = try RecordingWriter(url: file)
        var invalidTime = sample(10)
        invalidTime.timestamp = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try writer.append(invalidTime))
        var invalidRate = sample(10)
        invalidRate.processes[0].diskReadBytesPerSecond = -1
        XCTAssertThrowsError(try writer.append(invalidRate))
        XCTAssertThrowsError(try writer.appendMarker(EventMarker(timestamp: Date(timeIntervalSince1970: .nan))))
        try writer.close()
    }

    func testInsufficientHeaderBudgetDoesNotCreateAFile() throws {
        XCTAssertThrowsError(try RecordingWriter(url: file, maxBytes: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRecordingRejectsRepeatedOrDecreasingMonotonicTimes() throws {
        let writer = try RecordingWriter(url: file)
        try writer.append(sample(10))
        XCTAssertThrowsError(try writer.append(sample(10)))
        XCTAssertThrowsError(try writer.append(sample(9)))
        try writer.close()
        for next in [10.0, 9.0] {
            try write(header + snapshotLine(sample(10)) + snapshotLine(sample(next)))
            XCTAssertThrowsError(try RecordingReader.read(url: file))
        }
    }

    func testBackwardWallClockDoesNotReorderOrFreezeHistory() throws {
        let history = SessionHistory(maxDuration: 10)
        var first = sample(10)
        first.timestamp = Date(timeIntervalSince1970: 100)
        history.append(first)
        history.mark(EventMarker(timestamp: Date(timeIntervalSince1970: 101), label: "old"))
        var second = sample(20)
        second.timestamp = Date(timeIntervalSince1970: 50)
        history.append(second)
        history.mark(EventMarker(timestamp: Date(timeIntervalSince1970: 51), label: "recent"))
        var third = sample(22)
        third.timestamp = Date(timeIntervalSince1970: 52)
        history.append(third)
        XCTAssertEqual(history.snapshots.map(\.monotonicTime), [20, 22])
        XCTAssertEqual(history.last(seconds: 5).map(\.monotonicTime), [20, 22])
        XCTAssertEqual(history.markers.map(\.label), ["recent"])
        let writer = try RecordingWriter(url: file)
        try writer.append(first)
        try writer.append(second)
        try writer.append(third)
        try writer.close()
        XCTAssertEqual(try RecordingReader.read(url: file).snapshots.map(\.monotonicTime), [10, 20, 22])
    }

    func testWriterStopsBeforeSizeLimitAndPreservesValidPrefix() throws {
        let writer = try RecordingWriter(url: file, maxBytes: 128)
        XCTAssertThrowsError(try writer.append(sample(10)))
        try writer.close()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertLessThanOrEqual((attributes[.size] as? NSNumber)?.intValue ?? .max, 128)
        XCTAssertNoThrow(try RecordingReader.read(url: file))
    }

    func testReaderRejectsOversizedFileBeforeParsing() throws {
        try write(header)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 100 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try RecordingReader.read(url: file))
    }

    func testReaderRejectsOversizedUnterminatedLine() throws {
        try write(header + String(repeating: " ", count: 8 * 1024 * 1024 + 1))
        XCTAssertThrowsError(try RecordingReader.read(url: file))
    }

    func testClosedWriterCannotAppend() throws {
        let writer = try RecordingWriter(url: file)
        try writer.close()
        XCTAssertThrowsError(try writer.append(sample(10)))
        XCTAssertNoThrow(try writer.close())
    }

    func testHistoryEvictsOldSamplesAndMarkersByAge() {
        let history = SessionHistory(maxDuration: 10)
        history.append(sample(10))
        history.mark(EventMarker(timestamp: Date(timeIntervalSince1970: 11), label: "old"))
        history.append(sample(12))
        history.append(sample(22))
        XCTAssertEqual(history.snapshots.map(\.monotonicTime), [12, 22])
        XCTAssertTrue(history.markers.isEmpty)
        XCTAssertEqual(history.last(seconds: 5).map(\.monotonicTime), [22])
        XCTAssertTrue(history.last(seconds: -1).isEmpty)
    }

    func testHistoryEvictsByBytesAndBoundsMarkerOnlySessions() {
        let history = SessionHistory(maxDuration: 100, maxBytes: 800)
        history.append(sample(10))
        history.append(sample(12))
        history.append(sample(14))
        XCTAssertFalse(history.snapshots.isEmpty)
        XCTAssertLessThan(history.snapshots.count, 3)
        XCTAssertEqual(history.snapshots.last?.monotonicTime, 14)
        XCTAssertLessThanOrEqual(history.estimatedBytes, 800)
        let markers = SessionHistory(maxDuration: 100, maxBytes: 256)
        for time in 1...20 {
            markers.mark(EventMarker(timestamp: Date(timeIntervalSince1970: Double(time)), label: String(repeating: "x", count: 64)))
        }
        XCTAssertGreaterThan(markers.markers.count, 0)
        XCTAssertLessThan(markers.markers.count, 20)
        XCTAssertLessThanOrEqual(markers.estimatedBytes, 256)
        XCTAssertEqual(markers.markers.last?.timestamp.timeIntervalSince1970, 20)
    }

    func testOversizedHistoryEntryIsDroppedWithoutBreakingBounds() {
        let history = SessionHistory(maxBytes: 128)
        history.append(sample(10, name: String(repeating: "x", count: 1_000)))
        history.mark(EventMarker(timestamp: Date(timeIntervalSince1970: 10), label: String(repeating: "x", count: 1_000)))
        XCTAssertTrue(history.snapshots.isEmpty)
        XCTAssertTrue(history.markers.isEmpty)
        XCTAssertEqual(history.estimatedBytes, 0)
    }
}
