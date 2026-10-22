import Foundation
import Darwin

/// Each fetch owns an ephemeral session; streaming bounds memory before appending bytes.
final class UpdateHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let initialURL: URL
    private let completed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var data = Data()
    private var failure: Error?
    private var redirects = 0
    private var errorResponse: HTTPURLResponse?
    private var errorResponseDate = Date()

    private init(url: URL, limit: Int) { self.initialURL = url; self.limit = limit }

    static func fetch(_ url: URL, limit: Int) throws -> Data {
        let delegate = UpdateHTTP(url: url, limit: limit)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("tawl/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let task = session.dataTask(with: request)
        task.resume()
        guard delegate.completed.wait(timeout: .now() + 32) == .success else {
            task.cancel()
            throw UpdateError(L10n.text("GitHub request timed out. Try again when online."))
        }
        delegate.lock.lock(); defer { delegate.lock.unlock() }
        if let failure = delegate.failure { throw failure }
        return delegate.data
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            let now = Date()
            if let limit = GitHubRateLimit.parse(response: http, now: now) {
                lock.lock(); failure = limit; lock.unlock()
                completionHandler(.cancel)
                return
            }
            // Secondary limits can be a 403 with only a JSON message. Read a bounded error body.
            if http.statusCode == 403 {
                lock.lock(); errorResponse = http; errorResponseDate = now; lock.unlock()
                completionHandler(.allow)
                return
            }
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(limit) else {
            lock.lock()
            failure = UpdateError(L10n.text("GitHub returned an unavailable or oversized response (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."))
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        lock.lock()
        if errorResponse != nil {
            let remaining = GitHubRateLimit.maximumErrorBodySize - data.count
            data.append(bytes.prefix(remaining))
            let oversized = bytes.count > remaining
            if oversized { failure = receivedError() }
            lock.unlock()
            if oversized { dataTask.cancel() }
            return
        }
        let oversized = bytes.count > limit - data.count
        if oversized { failure = UpdateError(L10n.text("GitHub response exceeded the download size limit.")) }
        else { data.append(bytes) }
        lock.unlock()
        if oversized { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        let url = request.url
        // Release downloads redirect to GitHub's signed asset storage; metadata must stay at its exact endpoint.
        let allowed = initialURL.host == "github.com" && redirects <= 4 && url?.scheme == "https" &&
            url?.host == "release-assets.githubusercontent.com" && url?.user == nil && url?.password == nil
        if !allowed {
            lock.lock(); failure = UpdateError(L10n.text("GitHub redirected outside the trusted release asset host.")); lock.unlock()
        }
        completionHandler(allowed ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if failure == nil { failure = errorResponse == nil ? error : receivedError() }
        lock.unlock()
        completed.signal()
    }

    /// Called with the lock held; bodies are used for classification, never displayed.
    private func receivedError() -> Error {
        if let http = errorResponse,
           let limit = GitHubRateLimit.parse(response: http, body: data, now: errorResponseDate) { return limit }
        return UpdateError(L10n.text("GitHub returned an unavailable or oversized response (HTTP \(errorResponse?.statusCode ?? 0))."))
    }
}

struct UpdateProcessResult {
    let status: Int32
    let output: String
}

enum UpdateProcess {
    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval) throws -> UpdateProcessResult {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-command-\(UUID().uuidString)")
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw UpdateError(L10n.text("Cannot create command output file.")) }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var exceededOutput = false
        while process.isRunning, Date() < deadline {
            var info = stat()
            if fstat(fd, &info) == 0, info.st_size > 1_048_576 { exceededOutput = true; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw UpdateError(exceededOutput ? L10n.text("Update command exceeded the output limit.") : L10n.text("Update command timed out; installation may need a manual retry."))
        }
        try output.seek(toOffset: 0)
        let bytes = try output.read(upToCount: 1_048_576) ?? Data()
        return UpdateProcessResult(status: process.terminationStatus, output: String(decoding: bytes, as: UTF8.self))
    }
}
