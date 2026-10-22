import XCTest
@testable import TawlCore

final class ClosureImpactExportTests: XCTestCase {
    let exportedAt = Date(timeIntervalSince1970: 1792680000)
    func fixture(elapsed: Int = 60, hostile: Bool = false, missing: Bool = false) throws -> ClosureImpact {
        let helper = ProcessClosureTests()
        var p = helper.process()
        if hostile {
            p.name = "Helper <script>alert(1)</script> & \"quoted\""
            p.applicationName = "Browser <img src=x onerror=alert(1)> 'test'"
        }
        let intent = try helper.prepare(helper.snapshot(p)).get()
        func sample(_ time: Double, after: Bool) -> Snapshot {
            var s = Snapshot(timestamp: Date(timeIntervalSince1970: time), monotonicTime: time)
            s.intervalSeconds = 2
            s.cpuPercent = missing ? nil : (after ? 25 : 75)
            s.pressure = missing ? .unknown : (after ? .normal : .warning)
            s.swapUsedBytes = missing ? nil : (after ? 19 * 1_073_741_824 : 20 * 1_073_741_824)
            s.swapOutBytesPerSecond = missing ? nil : (after ? 0 : 1_048_576)
            return s
        }
        var value = ClosureImpact(intent: intent, startedAt: 100, startedOn: exportedAt,
            history: stride(from: 70.0, through: 100.0, by: 2).map { sample($0, after: false) })
        if elapsed >= 2 {
            for t in stride(from: 102.0, through: 100 + Double(elapsed), by: 2) {
                value.observe(sample(t, after: true), now: t)
            }
        }
        value.advance(now: 100 + Double(elapsed))
        return value
    }
    func testReportContainsIdentityOutcomeAndAllBeforeAfterValues() throws {
        let html = ClosureImpactExporter.html(impact: try fixture(), status: .exitObserved, exportedAt: exportedAt)
        for value in ["Browser Helper", "Browser", "PID 42", "42:100", "Process exit confirmed",
                      "75.0%", "25.0%", "−50.0 pp", "20.0 GiB", "19.0 GiB", "−1.0 GiB",
                      "Normal", "Warning", "1.0 MiB/s", "0 B/s", "30 / 30 s", "60 / 60 s",
                      "System CPU", "Memory pressure", "Swap used", "Swap writes", "Measurement complete"] {
            XCTAssertTrue(html.contains(value), "Missing report field: \(value)")
        }
        XCTAssertEqual(html.components(separatedBy: "<svg ").count - 1, 4)
        XCTAssertEqual(html.components(separatedBy: "class=\"request-line\"").count - 1, 4)
        XCTAssertTrue(html.contains("alone does not prove causation"))
        XCTAssertFalse(html.contains("<script")); XCTAssertFalse(html.contains("src=\"http"))
    }
    func testUntrustedLabelsAndRejectionDetailsAreEscapedEverywhere() throws {
        let html = ClosureImpactExporter.html(impact: try fixture(hostile: true),
            status: .rejected("<svg onload=alert(1)> & \"failure\""), exportedAt: exportedAt)
        XCTAssertFalse(html.contains("<script>")); XCTAssertFalse(html.contains("<img src=x"))
        XCTAssertFalse(html.contains("<svg onload="))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&lt;svg onload=alert(1)&gt; &amp; &quot;failure&quot;"))
    }
    func testEnglishAndTurkishReportsLocalizeLabelsWithoutChangingEvidenceOrEscaping() throws {
        let english = try L10n.withLanguage(.english) {
            ClosureImpactExporter.html(impact: try fixture(hostile: true), status: .exitObserved, exportedAt: exportedAt)
        }
        let turkish = try L10n.withLanguage(.turkish) {
            ClosureImpactExporter.html(impact: try fixture(hostile: true), status: .exitObserved, exportedAt: exportedAt)
        }
        XCTAssertTrue(english.contains("<html lang=\"en\">"))
        XCTAssertTrue(english.contains("Affected application"))
        XCTAssertTrue(turkish.contains("<html lang=\"tr\">"))
        XCTAssertTrue(turkish.contains(try XCTUnwrap(TurkishCore.strings["Affected application"])))
        XCTAssertTrue(turkish.contains(try XCTUnwrap(TurkishCore.strings["Process exit confirmed"])))
        for html in [english, turkish] {
            XCTAssertTrue(html.contains("75.0%")); XCTAssertTrue(html.contains("25.0%"))
            XCTAssertTrue(html.contains("20.0 GiB")); XCTAssertTrue(html.contains("19.0 GiB"))
            XCTAssertTrue(html.contains("PID 42")); XCTAssertTrue(html.contains("42:100"))
            XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
            XCTAssertFalse(html.contains("<script>")); XCTAssertFalse(html.contains("<img src=x"))
            XCTAssertEqual(html.components(separatedBy: "<svg ").count - 1, 4)
        }
    }
    func testPartialAndUnknownSamplesCannotClaimCompletionOrMeasuredZero() throws {
        let html = ClosureImpactExporter.html(impact: try fixture(elapsed: 12, missing: true),
            status: .waitingForExit, exportedAt: exportedAt)
        XCTAssertTrue(html.contains("Partial report · 12 / 60 s"))
        XCTAssertTrue(html.contains("State at export time"))
        XCTAssertTrue(html.contains("No measurement")); XCTAssertTrue(html.contains("Not yet observed"))
        XCTAssertTrue(html.contains("Exit not yet confirmed"))
        XCTAssertFalse(html.contains("Measurement complete"))
        XCTAssertFalse(html.contains("data-observed="))
        XCTAssertTrue(html.contains("class=\"missing-region\""))
    }
    func testZeroIsAnObservedValueAndUnknownGapsAreNotConnected() throws {
        let helper = ClosureImpactTests()
        var value = try helper.impact([helper.point(100, cpu: 0, swap: 0, rate: 0)])
        value.observe(helper.point(102, cpu: 0, swap: 0, rate: 0), now: 102)
        value.observe(helper.point(110, cpu: 0, swap: 0, rate: 0), now: 110)
        let html = ClosureImpactExporter.html(impact: value, status: .stillRunning, exportedAt: exportedAt)
        XCTAssertTrue(html.contains("0.0%")); XCTAssertTrue(html.contains("0 B/s"))
        XCTAssertTrue(html.contains("data-observed=\"0.000\""))
        XCTAssertTrue(html.contains("class=\"missing-region\""))
        XCTAssertTrue(html.contains("Process still running at last check"))
        XCTAssertFalse(html.contains("<polyline"), "Separated interval segments must not bridge missing evidence")
    }
    func testExportIsAnImmutableSnapshotWithUniquePrivateFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-export-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("reports")
        var value = try fixture(elapsed: 12)
        let one = try ClosureImpactExporter.write(impact: value, status: .waitingForExit, directory: directory, exportedAt: exportedAt)
        let original = try Data(contentsOf: one)
        value.advance(now: 160)
        let two = try ClosureImpactExporter.write(impact: value, status: .exitObserved, directory: directory, exportedAt: exportedAt)
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(try Data(contentsOf: one), original)
        XCTAssertTrue(String(decoding: original, as: UTF8.self).contains("Partial report"))
        XCTAssertTrue(try String(contentsOf: two, encoding: .utf8).contains("Measurement complete"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: one.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual(one.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(one.pathExtension, "html")
    }
    func testExistingDirectoryPermissionsArePreservedAndSymlinkTargetIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-export-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        _ = try ClosureImpactExporter.write(impact: fixture(), status: .exitObserved, directory: root, exportedAt: exportedAt)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let count = try FileManager.default.contentsOfDirectory(atPath: root.path).count
        XCTAssertThrowsError(try ClosureImpactExporter.write(impact: fixture(), status: .exitObserved, directory: link, exportedAt: exportedAt))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, count)
    }
    func testCaptureReportsWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["TAWL_EXPORT_CAPTURE"] else { return }
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, impact, status) in [("complete", try fixture(), ProcessClosureStatus.exitObserved),
                                       ("partial-missing", try fixture(elapsed: 12, missing: true), .unverified)] {
            try ClosureImpactExporter.html(impact: impact, status: status, exportedAt: exportedAt)
                .write(to: root.appendingPathComponent(name + ".html"), atomically: true, encoding: .utf8)
        }
    }
}
