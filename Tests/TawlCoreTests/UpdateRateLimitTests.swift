import XCTest
import Foundation
import Darwin
@testable import TawlCore

final class UpdateRateLimitTests: XCTestCase {
    func testPrimaryLimitExplainsRetryTimeAndHomebrewAlternativeThroughRealHTTP() throws {
        let server = try RateLimitHTTPServer(status: 403, headers: [
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": String(Int(Date().addingTimeInterval(300).timeIntervalSince1970))
        ])
        defer { server.stop() }
        let service = makeService(server: server)
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try service.check()) { error in
                let message = error.localizedDescription
                XCTAssertTrue(message.lowercased().contains("rate limit"), message)
                XCTAssertTrue(message.lowercased().contains("retry"), message)
                XCTAssertTrue(message.contains("brew update && brew upgrade phalegethon/tawl/tawl"), message)
                XCTAssertNotNil(message.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} (Z|[+-]\d{2}:\d{2})"#, options: .regularExpression), message)
            }
        }
        XCTAssertEqual(server.requestCount, 1, "A quota failure must not trigger another HTTP request")
    }

    func testOrdinaryForbiddenResponseIsNotMislabelledAsQuotaFailure() throws {
        let server = try RateLimitHTTPServer(status: 403, headers: ["X-RateLimit-Remaining": "25"],
                                            body: #"{"message":"Resource not accessible by integration"}"#)
        defer { server.stop() }
        let service = makeService(server: server)
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try service.check()) { error in
                XCTAssertTrue(error.localizedDescription.contains("403"))
                XCTAssertFalse(error.localizedDescription.lowercased().contains("rate limit"))
                XCTAssertNil((error as? UpdateError)?.rateLimit)
            }
        }
        XCTAssertEqual(server.requestCount, 1)
    }

    func testTooManyRequestsUsesRetryAfterSecondsThroughRealHTTP() throws {
        let server = try RateLimitHTTPServer(status: 429, headers: ["rEtRy-AfTeR": "120"])
        defer { server.stop() }
        let started = Date()
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try makeService(server: server).check()) { error in
                let message = error.localizedDescription
                XCTAssertTrue(message.lowercased().contains("rate limit"), message)
                XCTAssertTrue(message.contains("tawl update check"), message)
                let deadline = (error as? UpdateError)?.rateLimit?.retryAt
                XCTAssertNotNil(deadline)
                if let deadline {
                    XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(started), 119)
                    XCTAssertLessThan(deadline.timeIntervalSince(started), 125)
                }
            }
        }
        XCTAssertEqual(server.requestCount, 1)
    }

    func testSecondaryLimitWithoutTimingGivesMinimumWaitAndDoesNotEchoBody() throws {
        let server = try RateLimitHTTPServer(status: 403,
            body: #"{"message":"You have exceeded a secondary rate limit. secret-response-marker"}"#)
        defer { server.stop() }
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try makeService(server: server).check()) { error in
                let message = error.localizedDescription
                XCTAssertTrue(message.lowercased().contains("rate limit"), message)
                XCTAssertTrue(message.lowercased().contains("at least 1 minute"), message)
                XCTAssertFalse(message.contains("secret-response-marker"), message)
                XCTAssertNotNil((error as? UpdateError)?.rateLimit)
                XCTAssertNil((error as? UpdateError)?.rateLimit?.retryAt)
            }
        }
    }

    func testTurkishWarningPreservesActionableCommands() throws {
        let server = try RateLimitHTTPServer(status: 429)
        defer { server.stop() }
        try L10n.withLanguage(.turkish) {
            XCTAssertThrowsError(try makeService(server: server).check()) { error in
                let message = error.localizedDescription
                XCTAssertFalse(message.contains("GitHub API rate limit"), message)
                XCTAssertTrue(message.contains("GitHub"), message)
                XCTAssertTrue(message.contains("1 dakika"), message)
                XCTAssertTrue(message.contains("tawl update check"), message)
                XCTAssertTrue(message.contains("brew update && brew upgrade phalegethon/tawl/tawl"), message)
            }
        }
    }

    func testBackgroundLimitNoticeIsCachedAndDoesNotRepeatHTTPOrRunHomebrew() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-rate-limit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("updates.json")
        let server = try RateLimitHTTPServer(status: 429, headers: ["Retry-After": "120"])
        defer { server.stop() }
        let service = makeService(server: server, cache: cache)
        L10n.withLanguage(.english) { service.performAutomaticCheck() }
        XCTAssertTrue(service.notice?.contains("rate limit") == true, service.notice ?? "No notice")
        XCTAssertTrue(service.notice?.contains("tawl update check") == true, service.notice ?? "No notice")
        let cached = makeService(server: server, cache: cache, transport: { _, _ in
            XCTFail("A cached rate-limit response must suppress another network request")
            throw URLError(.cannotConnectToHost)
        })
        L10n.withLanguage(.english) { cached.performAutomaticCheck() }
        XCTAssertEqual(cached.notice, service.notice)
        XCTAssertEqual(server.requestCount, 1)
    }

    func testParserUsesLaterOfRetryAfterAndExhaustedPrimaryReset() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (retrySeconds, resetSeconds) in [(120, 300), (300, 120)] {
            let response = httpResponse(status: 403, headers: [
                "Retry-After": String(retrySeconds), "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": String(Int(now.timeIntervalSince1970) + resetSeconds)
            ])
            let limit = try XCTUnwrap(GitHubRateLimit.parse(response: response, now: now))
            XCTAssertEqual(limit.retryAt, now.addingTimeInterval(300))
        }
    }

    func testParserSupportsHTTPDateAndGuidanceIncludesLocalOffset() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let retryAt = now.addingTimeInterval(150)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let response = httpResponse(status: 429, headers: ["Retry-After": formatter.string(from: retryAt)])
        let limit = try XCTUnwrap(GitHubRateLimit.parse(response: response, now: now))
        XCTAssertEqual(limit.retryAt, retryAt)
        let guidance = L10n.withLanguage(.english) {
            limit.guidance(now: now, timeZone: TimeZone(secondsFromGMT: 10_800)!)
        }
        XCTAssertTrue(guidance.contains("+03:00"), guidance)
        XCTAssertTrue(guidance.contains("about 3 min"), guidance)
        XCTAssertTrue(guidance.contains("tawl update check"), guidance)
    }

    func testMissingInvalidAndPastDeadlinesRemainUnknown() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let headers: [[String: String]] = [[:], ["Retry-After": "-10"], ["Retry-After": "NaN"],
            ["Retry-After": "Infinity"], ["Retry-After": "1.5"], ["Retry-After": "0"],
            ["Retry-After": String(repeating: "9", count: 400)],
            ["Retry-After": "yesterday"], ["Retry-After": "Fri, 31 Dec 1999 23:59:59 GMT"],
            ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "-1"],
            ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(Int(now.timeIntervalSince1970) - 1)],
            ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "NaN"]]
        for fields in headers {
            let limit = try XCTUnwrap(GitHubRateLimit.parse(response: httpResponse(status: 429, headers: fields), now: now))
            XCTAssertNil(limit.retryAt, "Invalid timing must not invent a retry deadline: \(fields)")
        }
    }

    func testPreviouslyKnownWaitExpiresWithoutInventingAnotherWait() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let limit = GitHubRateLimit(statusCode: 429, retryAt: now.addingTimeInterval(-1))
        L10n.withLanguage(.english) {
            XCTAssertTrue(limit.guidance(now: now).contains("wait has ended"))
            XCTAssertTrue(limit.notice(now: now).contains("retry now"))
            XCTAssertFalse(limit.guidance(now: now).contains("at least 1 minute"))
        }
        L10n.withLanguage(.turkish) {
            XCTAssertTrue(limit.guidance(now: now).contains("Bekleme süresi doldu"))
            XCTAssertTrue(limit.notice(now: now).contains("şimdi dene"))
        }
    }

    func testStandaloneInstallationDoesNotSuggestHomebrewAsItsUpdater() throws {
        let server = try RateLimitHTTPServer(status: 429)
        defer { server.stop() }
        let service = makeService(server: server, executablePath: "/tmp/tawl-test/bin/tawl")
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try service.check()) { error in
                let message = error.localizedDescription
                XCTAssertTrue(message.contains("tawl update check"), message)
                XCTAssertTrue(message.contains("Installed TAWL 0.2.0 was left unchanged"), message)
                XCTAssertFalse(message.contains("brew upgrade"), message)
            }
        }
    }

    func testOversizedForbiddenBodyIsBoundedAndNotEchoedThroughRealHTTP() throws {
        let body = #"{"message":"secondary rate limit exceeded","padding":""# + String(repeating: "x", count: 32_768) + #""}"#
        let server = try RateLimitHTTPServer(status: 403, body: body)
        defer { server.stop() }
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try makeService(server: server).check()) { error in
                XCTAssertTrue(error.localizedDescription.contains("403"))
                XCTAssertFalse(error.localizedDescription.contains("padding"))
                XCTAssertNil((error as? UpdateError)?.rateLimit)
            }
        }
        XCTAssertEqual(server.requestCount, 1)
    }

    func testResetHeaderAloneDoesNotMakeOrdinaryForbiddenResponseARateLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for status in [200, 401, 403, 404, 500] {
            let response = httpResponse(status: status, headers: [
                "X-RateLimit-Remaining": "12", "X-RateLimit-Reset": String(Int(now.timeIntervalSince1970) + 300)
            ])
            XCTAssertNil(GitHubRateLimit.parse(response: response, now: now), "HTTP \(status)")
        }
        let secondary = GitHubRateLimit.parse(response: httpResponse(status: 429, headers: [
            "X-RateLimit-Remaining": "12", "X-RateLimit-Reset": String(Int(now.timeIntervalSince1970) + 300)
        ]), now: now)
        XCTAssertNotNil(secondary)
        XCTAssertNil(secondary?.retryAt, "A non-exhausted primary reset does not describe a secondary limit's deadline")
    }

    func testSecondaryBodyRecognitionIsBoundedAndRequiresMessageField() {
        let response = httpResponse(status: 403)
        XCTAssertNotNil(GitHubRateLimit.parse(response: response, body: Data(#"{"message":"secondary rate limit exceeded"}"#.utf8)))
        XCTAssertNil(GitHubRateLimit.parse(response: response, body: Data(#"{"documentation_url":"rate limit","message":"Forbidden"}"#.utf8)))
        XCTAssertNil(GitHubRateLimit.parse(response: response, body: Data("rate limit".utf8)))
        let oversized = #"{"message":"secondary rate limit exceeded","padding":""# + String(repeating: "a", count: 17_000) + #""}"#
        XCTAssertNil(GitHubRateLimit.parse(response: response, body: Data(oversized.utf8)))
    }

    private func httpResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: UpdateService.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeService(server: RateLimitHTTPServer, cache: URL? = nil,
                             executablePath: String = "/opt/homebrew/Cellar/tawl/0.2.0/bin/tawl",
                             transport: ((URL, Int) throws -> Data)? = nil) -> UpdateService {
        UpdateService(currentVersion: "0.2.0", architecture: "arm64",
                      executableURL: URL(fileURLWithPath: executablePath),
                      cacheURL: cache, environment: [:], homebrewURL: nil,
                      transport: transport ?? { url, limit in
            XCTAssertEqual(url, UpdateService.endpoint)
            return try UpdateHTTP.fetch(server.url, limit: limit)
        }, runner: { _, _, _ in
            XCTFail("A rate-limit warning must not run Homebrew or any other subprocess")
            return UpdateProcessResult(status: 1, output: "unexpected subprocess")
        })
    }
}

/// A single bounded response on loopback exercises URLSession without contacting GitHub.
private final class RateLimitHTTPServer {
    let url: URL
    private let listener: Int32
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    private var stopped = false

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }

    init(status: Int, headers: [String: String] = [:], body: String = "{}") throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        self.listener = listener
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 1) == 0 else {
            Darwin.close(listener); throw POSIXError(.EIO)
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listener, $0, &length)
            }
        }
        guard named == 0 else { Darwin.close(listener); throw POSIXError(.EIO) }
        url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))/release")!
        let fields = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined()
        let response = Data(("HTTP/1.1 \(status) Test\r\n" + fields +
            "Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body).utf8)
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { finished.signal() }
            var wait = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&wait, 1, 5_000) > 0, wait.revents & Int16(POLLIN) != 0 else { return }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { Darwin.close(client) }
            var noSignal: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var readWait = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            guard poll(&readWait, 1, 5_000) > 0 else { return }
            var request = [UInt8](repeating: 0, count: 8_192)
            guard recv(client, &request, request.count, 0) > 0 else { return }
            lock.lock(); count += 1; lock.unlock()
            response.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var sent = 0
                while sent < bytes.count {
                    let size = Darwin.send(client, base.advanced(by: sent), bytes.count - sent, 0)
                    guard size > 0 else { break }
                    sent += size
                }
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        _ = Darwin.shutdown(listener, SHUT_RDWR)
        _ = finished.wait(timeout: .now() + 6)
        Darwin.close(listener)
    }
}
