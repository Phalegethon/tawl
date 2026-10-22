import XCTest
import CryptoKit
import Darwin
@testable import TawlCore

final class UpdateTests: XCTestCase {
    func testSemanticVersionsCompareNumericallyAndRespectPrerelease() throws {
        XCTAssertTrue(try SemanticVersion("1.9.0") < SemanticVersion("1.10.0"))
        XCTAssertTrue(try SemanticVersion("1.0.0-rc.9") < SemanticVersion("1.0.0-rc.10"))
        XCTAssertTrue(try SemanticVersion("1.0.0-rc.10") < SemanticVersion("1.0.0"))
        XCTAssertEqual(try SemanticVersion("1.0.0+build.1"), try SemanticVersion("1.0.0+build.2"))
        for invalid in ["1.2", "01.2.3", "1.2.3-01", "1.2.3/evil", "1.2.3-", "1.2.3+", " 1.2.3"] {
            XCTAssertThrowsError(try SemanticVersion(invalid), invalid)
        }
    }

    func testCheckUsesOfficialEndpointAndReportsNewReleaseWithoutDigestRequirement() throws {
        let service = makeService { url, limit in
            XCTAssertEqual(url.absoluteString, "https://api.github.com/repos/Phalegethon/tawl/releases/latest")
            XCTAssertEqual(limit, 1_048_576)
            return self.release(digest: nil)
        }
        let result = try service.check()
        XCTAssertTrue(result.isUpdateAvailable)
        XCTAssertEqual(result.latestVersion, "0.2.0")
        XCTAssertTrue(result.message.contains("tawl update"))
    }

    func testLocalizedUpdateMessagesPreserveVersionsCommandsAndCachedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-localized-update-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("check.json")
        let english = makeService(cache: cache) { _, _ in self.release() }
        let result = try L10n.withLanguage(.english) { try english.check() }
        L10n.withLanguage(.english) { english.performAutomaticCheck() }
        XCTAssertEqual(english.notice, "New release · tawl update · v0.2.0")
        let turkish = makeService(cache: cache) { _, _ in
            XCTFail("Language changes must reuse language-neutral release metadata")
            return Data()
        }
        L10n.withLanguage(.turkish) { turkish.performAutomaticCheck() }
        let template = try XCTUnwrap(TurkishUpdates.strings["New release · tawl update · v{0}"])
        XCTAssertEqual(turkish.notice, template.replacingOccurrences(of: "{0}", with: "0.2.0"))
        XCTAssertEqual(result.latestVersion, "0.2.0")
        XCTAssertTrue(result.isUpdateAvailable)
        XCTAssertTrue(result.message.contains("`tawl update`"))
        XCTAssertTrue(turkish.notice?.contains("tawl update") == true)
    }

    func testUnavailableMalformedAndUnstableMetadataNeverClaimsCurrent() {
        let badPayloads: [Data] = [Data("{}".utf8), release(draft: true), release(prerelease: true), release(version: "0.2.0-beta.1")]
        for payload in badPayloads {
            XCTAssertThrowsError(try makeService { _, _ in payload }.check())
        }
        XCTAssertThrowsError(try makeService { _, _ in throw URLError(.notConnectedToInternet) }.check())
    }

    func testEqualAndOlderReleasesAreNotAnUpdate() throws {
        for version in ["0.1.0", "0.0.9"] {
            let result = try makeService { _, _ in self.release(version: version) }.check()
            XCTAssertFalse(result.isUpdateAvailable)
        }
    }

    func testStandaloneUpdateVerifiesAndAtomicallyReplacesInstalledBinary() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let payload = macho()
        var executed: [String] = []
        let service = makeService(executable: fixture.binary, transport: { url, _ in
            url.host == "api.github.com" ? self.release(digest: self.digest(payload)) : payload
        }, runner: { url, args, _ in
            executed = args
            XCTAssertNotEqual(url, fixture.binary)
            XCTAssertEqual(try Data(contentsOf: fixture.binary), Data("original".utf8))
            return UpdateProcessResult(status: 0, output: "tawl 0.2.0\n")
        })
        XCTAssertTrue(try service.apply().contains("0.2.0"))
        XCTAssertEqual(try Data(contentsOf: fixture.binary), payload)
        XCTAssertEqual(executed, ["--version"])
        let mode = try FileManager.default.attributesOfItem(atPath: fixture.binary.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o755)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.binary.deletingLastPathComponent().path), ["tawl"])
    }

    func testMissingDigestWrongDigestAndWrongArchitectureLeaveOriginalUntouched() throws {
        for failure in ["missing", "digest", "architecture", "version"] {
            let fixture = try installation()
            defer { try? FileManager.default.removeItem(at: fixture.prefix) }
            let payload = macho(architecture: failure == "architecture" ? "x86_64" : "arm64")
            let hash = failure == "missing" ? nil : failure == "digest" ? "sha256:" + String(repeating: "0", count: 64) : digest(payload)
            var executions = 0
            let service = makeService(executable: fixture.binary, transport: { url, _ in
                url.host == "api.github.com" ? self.release(digest: hash) : payload
            }, runner: { _, _, _ in
                executions += 1
                return UpdateProcessResult(status: 0, output: "tawl 999.0.0\n")
            })
            XCTAssertThrowsError(try service.apply(), failure)
            XCTAssertEqual(try Data(contentsOf: fixture.binary), Data("original".utf8), failure)
            XCTAssertEqual(executions, failure == "version" ? 1 : 0)
        }
    }

    func testUntrustedDownloadURLAndWrongAssetNameNeverDownloadOrExecute() throws {
        for address in ["http://github.com/Phalegethon/tawl/releases/download/v0.2.0/tawl-0.2.0-macos-arm64", "https://github.com/evil/tawl/releases/download/v0.2.0/tawl-0.2.0-macos-arm64", "https://github.com/Phalegethon/tawl/releases/download/v0.2.0/tawl-0.2.0-macos-arm64?evil=1"] {
            let fixture = try installation()
            defer { try? FileManager.default.removeItem(at: fixture.prefix) }
            let service = makeService(executable: fixture.binary) { url, _ in
                XCTAssertEqual(url.host, "api.github.com")
                return self.release(digest: self.digest(self.macho()), assetURL: address)
            }
            XCTAssertThrowsError(try service.apply())
        }
    }

    func testUnknownLocationSymlinkAndForeignReceiptRefuseSelfReplacement() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let noFetch: (URL, Int) throws -> Data = { _, _ in XCTFail("Invalid installation must fail before network access"); return Data() }
        let unknown = fixture.prefix.appendingPathComponent("development-tawl")
        XCTAssertThrowsError(try makeService(executable: unknown, transport: noFetch).apply())
        let link = fixture.binary.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.binary)
        XCTAssertThrowsError(try makeService(executable: link, transport: noFetch).apply())
        try Data("{\"schemaVersion\":1,\"method\":\"standalone\",\"repository\":\"someone/else\"}".utf8).write(to: fixture.receipt)
        XCTAssertThrowsError(try makeService(executable: fixture.binary, transport: noFetch).apply())
    }

    func testNoDowngradeOrEqualVersionExecution() throws {
        for version in ["0.1.0", "0.0.9"] {
            let fixture = try installation()
            defer { try? FileManager.default.removeItem(at: fixture.prefix) }
            let service = makeService(executable: fixture.binary) { url, _ in
                XCTAssertEqual(url.host, "api.github.com")
                return self.release(version: version)
            }
            XCTAssertThrowsError(try service.apply())
            XCTAssertEqual(try Data(contentsOf: fixture.binary), Data("original".utf8))
        }
    }

    func testHomebrewDelegatesFixedCommandsAndNeverDownloadsBinary() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let brew = fixture.prefix.appendingPathComponent("bin/brew")
        try Data().write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let executable = fixture.prefix.appendingPathComponent("Cellar/tawl/0.1.0/bin/tawl")
        var calls: [[String]] = []
        let service = makeService(executable: executable, brew: brew, transport: { _, _ in
            XCTFail("Homebrew owns its own metadata and downloads"); return Data()
        }, runner: { command, args, _ in
            if args == ["--version"] {
                XCTAssertEqual(command, fixture.prefix.appendingPathComponent("bin/tawl"))
                return UpdateProcessResult(status: 0, output: "tawl 0.2.0\n")
            }
            calls.append(args)
            if args == ["info", "--json=v2", "phalegethon/tawl/tawl"] {
                XCTAssertEqual(command, brew)
                return UpdateProcessResult(status: 0, output: #"{"formulae":[{"full_name":"phalegethon/tawl/tawl","versions":{"stable":"0.2.0"}}]}"#)
            }
            XCTAssertEqual(command, args.first == "HOMEBREW_NO_AUTO_UPDATE=1" ? URL(fileURLWithPath: "/usr/bin/env") : brew)
            return UpdateProcessResult(status: 0, output: "")
        })
        XCTAssertTrue(try service.apply(expectedVersion: "0.2.0").contains("Homebrew"))
        XCTAssertEqual(calls, [["update"], ["info", "--json=v2", "phalegethon/tawl/tawl"], ["HOMEBREW_NO_AUTO_UPDATE=1", brew.path, "upgrade", "phalegethon/tawl/tawl"]])
    }

    func testChangedReleaseAfterConfirmationDoesNotInstallDifferentVersion() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let service = makeService(executable: fixture.binary) { url, _ in
            XCTAssertEqual(url.host, "api.github.com")
            return self.release(version: "0.3.0")
        }
        XCTAssertThrowsError(try service.apply(expectedVersion: "0.2.0")) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed from 0.2.0 to 0.3.0"))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.binary), Data("original".utf8))
    }

    func testHomebrewNoOpDoesNotClaimNewVersionWasInstalled() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let brew = fixture.prefix.appendingPathComponent("bin/brew")
        try Data().write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let service = makeService(executable: fixture.prefix.appendingPathComponent("Cellar/tawl/0.1.0/bin/tawl"), brew: brew,
                                  transport: { _, _ in self.release() },
                                  runner: { _, args, _ in
            if args.first == "info" { return UpdateProcessResult(status: 0, output: #"{"formulae":[{"full_name":"phalegethon/tawl/tawl","versions":{"stable":"0.2.0"}}]}"#) }
            return UpdateProcessResult(status: 0, output: args == ["--version"] ? "tawl 0.1.0\n" : "Already up-to-date.\n")
        })
        XCTAssertThrowsError(try service.apply(expectedVersion: "0.2.0")) { error in
            XCTAssertTrue(error.localizedDescription.contains("0.1.0"))
            XCTAssertTrue(error.localizedDescription.contains("0.2.0"))
        }
    }

    func testHomebrewFormulaDriftRejectsBeforeUpgrade() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let brew = fixture.prefix.appendingPathComponent("bin/brew")
        try Data().write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        var calls: [[String]] = []
        let service = makeService(executable: fixture.prefix.appendingPathComponent("Cellar/tawl/0.1.0/bin/tawl"), brew: brew,
                                  transport: { _, _ in XCTFail("Homebrew preflight owns metadata lookup"); return Data() },
                                  runner: { command, args, _ in
            calls.append(args)
            XCTAssertEqual(command, brew)
            return UpdateProcessResult(status: 0, output: #"{"formulae":[{"full_name":"phalegethon/tawl/tawl","versions":{"stable":"0.3.0"}}]}"#)
        })
        XCTAssertThrowsError(try service.apply(expectedVersion: "0.2.0")) { error in
            XCTAssertTrue(error.localizedDescription.contains("0.3.0"))
            XCTAssertTrue(error.localizedDescription.contains("0.2.0"))
        }
        XCTAssertEqual(calls, [["update"], ["info", "--json=v2", "phalegethon/tawl/tawl"]])
        XCTAssertEqual(try Data(contentsOf: fixture.binary), Data("original".utf8))
    }

    func testAutomaticCheckIsOptOutAndCacheIsVersionAndSourceIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("updates.json")
        let first = makeService(cache: cache) { _, _ in self.release() }
        first.performAutomaticCheck()
        XCTAssertNotNil(first.notice)
        XCTAssertTrue(first.notice?.prefix(35).contains("tawl update") == true)
        let cached = makeService(cache: cache) { _, _ in XCTFail("Cache must throttle for 24 hours"); return Data() }
        cached.performAutomaticCheck()
        XCTAssertNotNil(cached.notice)
        let optedOut = makeService(cache: cache, environment: ["TAWL_NO_UPDATE_CHECK":"1"]) { _, _ in XCTFail("Opt out must not connect"); return Data() }
        optedOut.performAutomaticCheck()
        XCTAssertNil(optedOut.notice)
        var stale = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        stale["installedVersion"] = "9.0.0"
        try JSONSerialization.data(withJSONObject: stale).write(to: cache)
        let fresh = makeService(cache: cache) { _, _ in self.release(version: "0.3.0") }
        fresh.performAutomaticCheck()
        XCTAssertTrue(fresh.notice?.contains("0.3.0") == true)
    }

    func testFailedAutomaticCheckIsThrottledWithoutFalseUpToDateNotice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("updates.json")
        let first = makeService(cache: cache) { _, _ in throw URLError(.notConnectedToInternet) }
        first.performAutomaticCheck()
        XCTAssertNil(first.notice)
        let second = makeService(cache: cache) { _, _ in XCTFail("Failed checks are throttled too"); return Data() }
        second.performAutomaticCheck()
        XCTAssertNil(second.notice)
    }

    func testMalformedMachOLoadCommandsAreRejectedBeforeExecution() throws {
        var payload = macho()
        payload[16] = 1 // one load command
        payload[20] = 16 // sixteen bytes declared
        payload[36] = 4 // cmdsize smaller than the eight-byte load-command header
        XCTAssertThrowsError(try UpdateService.validateMachO(payload, architecture: "arm64"))
    }

    func testTamperingWithStagedBinaryDuringVersionProbeLeavesOriginalUntouched() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let payload = macho()
        let service = makeService(executable: fixture.binary, transport: { url, _ in
            url.host == "api.github.com" ? self.release(digest: self.digest(payload)) : payload
        }, runner: { url, _, _ in
            try Data(repeating: 0, count: payload.count).write(to: url)
            return UpdateProcessResult(status: 0, output: "tawl 0.2.0\n")
        })
        XCTAssertThrowsError(try service.apply())
        XCTAssertEqual(try Data(contentsOf: fixture.binary), Data("original".utf8))
    }

    func testProcessRunnerUsesArgumentBoundariesAndBoundsWait() throws {
        let result = try UpdateProcess.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "literal $(not-a-command); text"], timeout: 1)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "literal $(not-a-command); text")
        let started = Date()
        XCTAssertThrowsError(try UpdateProcess.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testUnwritableBinaryAndSymlinkedReceiptFailBeforeNetwork() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let service = makeService(executable: fixture.binary) { _, _ in XCTFail("Unsafe targets must be refused before downloads"); return Data() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.binary.path)
        XCTAssertThrowsError(try service.apply())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.binary.path)
        let saved = fixture.prefix.appendingPathComponent("receipt.json")
        try FileManager.default.moveItem(at: fixture.receipt, to: saved)
        try FileManager.default.createSymbolicLink(at: fixture.receipt, withDestinationURL: saved)
        XCTAssertThrowsError(try service.apply())
    }

    func testStandaloneUpdateCanLaunchARealStagedMachOBinary() throws {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        let source = fixture.prefix.appendingPathComponent("version.c")
        let compiled = fixture.prefix.appendingPathComponent("version")
        try Data("int puts(const char *); int main(void) { puts(\"tawl 0.2.0\"); return 0; }".utf8).write(to: source)
        let compilation = try UpdateProcess.run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["clang", "-arch", architecture, source.path, "-o", compiled.path], timeout: 20)
        XCTAssertEqual(compilation.status, 0, compilation.output)
        let payload = try Data(contentsOf: compiled)
        let service = makeService(executable: fixture.binary, architecture: architecture, transport: { url, _ in
            url.host == "api.github.com" ? self.release(digest: self.digest(payload), size: payload.count, architecture: architecture) : payload
        }, runner: UpdateProcess.run)
        XCTAssertTrue(try service.apply().contains("0.2.0"))
        let installed = try UpdateProcess.run(fixture.binary, arguments: ["--version"], timeout: 2)
        XCTAssertEqual(installed.output, "tawl 0.2.0\n")
    }

    func testBooleanReceiptSchemaDoesNotAuthorizeBinaryReplacement() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        try Data("{\"schemaVersion\":true,\"method\":\"standalone\",\"repository\":\"Phalegethon/tawl\"}".utf8).write(to: fixture.receipt)
        let service = makeService(executable: fixture.binary) { _, _ in XCTFail("Invalid receipt must fail before network access"); return Data() }
        XCTAssertThrowsError(try service.apply())
    }

    func testFIFOReceiptIsRejectedWithoutBlockingOrNetworkAccess() throws {
        let fixture = try installation()
        defer { try? FileManager.default.removeItem(at: fixture.prefix) }
        try FileManager.default.removeItem(at: fixture.receipt)
        XCTAssertEqual(mkfifo(fixture.receipt.path, 0o600), 0)
        let service = makeService(executable: fixture.binary) { _, _ in XCTFail("A FIFO cannot authorize an install"); return Data() }
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            do { _ = try service.apply(); XCTFail("FIFO receipt was accepted") } catch { }
            finished.signal()
        }
        let outcome = finished.wait(timeout: .now() + 0.5)
        if outcome != .success { // Unblock a regressed implementation so the test cannot leak a waiting reader.
            let writer = open(fixture.receipt.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
        }
        XCTAssertEqual(outcome, .success)
    }

    func testAutomaticCacheRejectsForeignSourcesExpiredDatesAndPrereleaseVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("updates.json")
        for mutation in ["source", "expired", "prerelease"] {
            let initial = makeService(cache: cache) { _, _ in self.release() }
            try? FileManager.default.removeItem(at: cache)
            initial.performAutomaticCheck()
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
            switch mutation {
            case "source": object["source"] = "https://example.com/other-releases"
            case "expired": object["checkedAt"] = Date().addingTimeInterval(-86401).timeIntervalSinceReferenceDate
            default: object["latestVersion"] = "9.0.0-beta.1"
            }
            try JSONSerialization.data(withJSONObject: object).write(to: cache)
            let service = makeService(cache: cache) { _, _ in self.release(version: "0.3.0") }
            service.performAutomaticCheck()
            XCTAssertTrue(service.notice?.contains("0.3.0") == true, mutation)
        }
    }

    private func makeService(executable: URL = URL(fileURLWithPath: "/unknown/tawl"), cache: URL? = nil, brew: URL? = nil, environment: [String:String] = [:], architecture: String = "arm64", transport: @escaping (URL, Int) throws -> Data, runner: @escaping (URL, [String], TimeInterval) throws -> UpdateProcessResult = { _, _, _ in XCTFail("Unexpected process"); return UpdateProcessResult(status: 1, output: "") }) -> UpdateService {
        UpdateService(currentVersion: "0.1.0", architecture: architecture, executableURL: executable, cacheURL: cache, environment: environment, homebrewURL: brew, transport: transport, runner: runner)
    }

    private func release(version: String = "0.2.0", draft: Bool = false, prerelease: Bool = false, digest: String? = nil, assetURL: String? = nil, size: Int = 64, architecture: String = "arm64") -> Data {
        var asset: [String: Any] = ["name": "tawl-\(version)-macos-\(architecture)", "size": size, "browser_download_url": assetURL ?? "https://github.com/Phalegethon/tawl/releases/download/v\(version)/tawl-\(version)-macos-\(architecture)"]
        if let digest { asset["digest"] = digest }
        return try! JSONSerialization.data(withJSONObject: ["tag_name":"v\(version)", "draft":draft, "prerelease":prerelease, "assets":[asset]])
    }

    private func digest(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func macho(architecture: String = "arm64") -> Data {
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes.replaceSubrange(0..<4, with: [0xcf,0xfa,0xed,0xfe])
        bytes.replaceSubrange(4..<8, with: architecture == "arm64" ? [0x0c,0,0,1] : [7,0,0,1])
        bytes[12] = 2 // MH_EXECUTE
        bytes[16] = 1 // one load command
        bytes[20] = 24
        bytes.replaceSubrange(32..<36, with: [0x28, 0, 0, 0x80]) // LC_MAIN
        bytes[36] = 24
        return Data(bytes)
    }

    private func installation() throws -> (prefix: URL, binary: URL, receipt: URL) {
        let prefix = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let binary = prefix.appendingPathComponent("bin/tawl")
        let receipt = prefix.appendingPathComponent("share/tawl/install.json")
        for directory in [binary.deletingLastPathComponent(), receipt.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("original".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try Data("{\"schemaVersion\":1,\"method\":\"standalone\",\"repository\":\"Phalegethon/tawl\"}".utf8).write(to: receipt)
        return (prefix, binary, receipt)
    }
}
