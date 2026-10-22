import XCTest
@testable import TawlCore
final class OptionsTests: XCTestCase {
    func testVersionAndUpdateCommandsDoNotAcceptMonitoringFlags() throws {
        XCTAssertEqual(try CLIOptions.parse(["--version"]).command, "version")
        XCTAssertEqual(try CLIOptions.parse(["version"]).command, "version")
        XCTAssertEqual(try CLIOptions.parse(["update", "check"]).command, "update-check")
        XCTAssertEqual(try CLIOptions.parse(["update", "--check"]).command, "update-check")
        XCTAssertEqual(try CLIOptions.parse(["update"]).command, "update")
        XCTAssertFalse(try CLIOptions.parse(["update"]).assumeYes)
        XCTAssertTrue(try CLIOptions.parse(["update", "--yes"]).assumeYes)
        XCTAssertTrue(try CLIOptions.parse(["--no-update-check"]).noUpdateCheck)
        XCTAssertFalse(try CLIOptions.parse([]).noUpdateCheck)
        for args in [["version", "--json"], ["--version", "oops"], ["update", "status"],
                     ["update", "--sample", "3s"], ["update", "check", "--yes"],
                     ["update", "--check", "--yes"], ["update", "--yes", "--yes"],
                     ["update", "--check", "check"], ["status", "--no-update-check"]] {
            XCTAssertThrowsError(try CLIOptions.parse(args), "\(args)")
        }
    }
    func testCommandsHaveStrictFlagsAndDurations() throws {
        let s = try CLIOptions.parse(["status", "--sample", "3s", "--json"])
        XCTAssertEqual(s.command,"status"); XCTAssertEqual(s.sampleSeconds,3); XCTAssertTrue(s.json)
        let r = try CLIOptions.parse(["record","--duration","2m","--output","a.tawl"])
        XCTAssertEqual(r.durationSeconds,120); XCTAssertEqual(r.output,"a.tawl")
        let report = try CLIOptions.parse(["report","a.tawl","--last","5m"])
        XCTAssertEqual(report.input,"a.tawl"); XCTAssertEqual(report.lastSeconds,300)
    }
    func testInvalidOrAmbiguousInputIsRejected() {
        for args in [["oops"],["status","--sample","nan"],["status","--sample","0s"],["status","--sample","16s"], ["status","--sample","1s","--sample","2s"],["record"],["report"],["watch","--json"],["report","a","b"],["status","--last","2m"]] {
            XCTAssertThrowsError(try CLIOptions.parse(args),"\(args)")
        }
    }
}
