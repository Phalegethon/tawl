import Foundation
import Darwin

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// SemVer precedence, including numeric prerelease identifiers; build metadata is ignored.
struct SemanticVersion: Comparable {
    let numbers: [String]
    let prerelease: [String]

    init(_ string: String) throws {
        let pattern = #"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"#
        let range = NSRange(string.startIndex..., in: string)
        guard string.utf8.count <= 200,
              let match = try NSRegularExpression(pattern: pattern).firstMatch(in: string, range: range), match.range == range else {
            throw UpdateError("Invalid release version: \(string.prefix(200))")
        }
        let core = string.split(separator: "+", maxSplits: 1)[0].split(separator: "-", maxSplits: 1)
        numbers = core[0].split(separator: ".").map(String.init)
        prerelease = core.count == 2 ? core[1].split(separator: ".").map(String.init) : []
        guard !prerelease.contains(where: { Self.numeric($0) && $0.count > 1 && $0.first == "0" }) else {
            throw UpdateError("Invalid numeric prerelease identifier.")
        }
    }

    private static func numeric(_ value: String) -> Bool { value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }
    private static func numericLess(_ a: String, _ b: String) -> Bool { a.count == b.count ? a < b : a.count < b.count }
    static func < (a: Self, b: Self) -> Bool {
        for (left, right) in zip(a.numbers, b.numbers) where left != right { return numericLess(left, right) }
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (left, right) in zip(a.prerelease, b.prerelease) where left != right {
            let ln = numeric(left), rn = numeric(right)
            if ln != rn { return ln }
            return ln ? numericLess(left, right) : left < right
        }
        return a.prerelease.count < b.prerelease.count
    }
}

public struct UpdateCheckResult {
    public let latestVersion: String
    public let isUpdateAvailable: Bool
    public let message: String
}

struct UpdateRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: String
        let digest: String?
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }

    func validatedVersion() throws -> SemanticVersion {
        let parsed = try SemanticVersion(version)
        guard !draft, !prerelease, parsed.prerelease.isEmpty else { throw UpdateError("Latest release metadata is not a stable published release.") }
        return parsed
    }
}

public final class UpdateService {
    static let endpoint = URL(string: "https://api.github.com/repos/\(BuildInfo.repository)/releases/latest")!
    static let maximumBinarySize = 100 * 1024 * 1024
    let currentVersion: String
    let architecture: String
    let executableURL: URL
    let cacheURL: URL?
    let environment: [String: String]
    let homebrewURL: URL?
    let transport: (URL, Int) throws -> Data
    let runner: (URL, [String], TimeInterval) throws -> UpdateProcessResult
    private let noticeLock = NSLock()
    private var storedNotice: String?
    private var automaticStarted = false

    public convenience init() {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let cache = caches?.appendingPathComponent("tawl/updates-Phalegethon-tawl-\(BuildInfo.version).json")
        self.init(currentVersion: BuildInfo.version, architecture: architecture,
                  executableURL: Self.actualExecutableURL(), cacheURL: cache,
                  environment: ProcessInfo.processInfo.environment, homebrewURL: nil,
                  transport: UpdateHTTP.fetch, runner: UpdateProcess.run)
    }

    init(currentVersion: String, architecture: String, executableURL: URL, cacheURL: URL?, environment: [String:String], homebrewURL: URL?, transport: @escaping (URL, Int) throws -> Data, runner: @escaping (URL, [String], TimeInterval) throws -> UpdateProcessResult) {
        self.currentVersion = currentVersion
        self.architecture = architecture
        self.executableURL = executableURL.standardizedFileURL
        self.cacheURL = cacheURL
        self.environment = environment
        self.homebrewURL = homebrewURL
        self.transport = transport
        self.runner = runner
    }

    public var notice: String? {
        noticeLock.lock(); defer { noticeLock.unlock() }
        return storedNotice
    }

    public func check() throws -> UpdateCheckResult {
        let release = try fetchRelease()
        return try result(for: release.version)
    }

    func fetchRelease() throws -> UpdateRelease {
        do {
            let data = try transport(Self.endpoint, 1_048_576)
            guard data.count <= 1_048_576 else { throw UpdateError("Release metadata exceeds the size limit.") }
            let release = try JSONDecoder().decode(UpdateRelease.self, from: data)
            _ = try release.validatedVersion()
            return release
        } catch {
            throw UpdateError("Update check unavailable; installed version is \(currentVersion). \(error.localizedDescription)")
        }
    }

    private func result(for latest: String) throws -> UpdateCheckResult {
        let latestVersion = try SemanticVersion(latest), installed = try SemanticVersion(currentVersion)
        let newer = latestVersion > installed
        let message = newer ? "TAWL \(latest) is available (installed \(currentVersion)). Run `tawl update` to install."
            : latestVersion == installed ? "TAWL \(currentVersion) is the latest published stable release."
            : "Installed TAWL \(currentVersion) is newer than the latest published stable release (\(latest))."
        return UpdateCheckResult(latestVersion: latest, isUpdateAvailable: newer, message: message)
    }

    public func startAutomaticCheck() {
        noticeLock.lock()
        guard !automaticStarted, environment["TAWL_NO_UPDATE_CHECK"] != "1" else { noticeLock.unlock(); return }
        automaticStarted = true
        noticeLock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in performAutomaticCheck() }
    }

    private struct Cache: Codable {
        let schemaVersion: Int
        let source: String
        let installedVersion: String
        let checkedAt: Date
        let latestVersion: String?
        var hasStableVersion: Bool {
            guard let latestVersion else { return true }
            return (try? SemanticVersion(latestVersion).prerelease.isEmpty) == true
        }
    }

    private func readCache(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_size > 0, info.st_size <= 8192 else { return nil }
        return try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: 8193)
    }

    /// Shared process lock makes simultaneous launches consume at most one daily check.
    func performAutomaticCheck() {
        guard environment["TAWL_NO_UPDATE_CHECK"] != "1" else { return }
        var lockFD: Int32 = -1
        if let cacheURL {
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                lockFD = open(cacheURL.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
                guard lockFD >= 0 else { return }
                guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); return }
            } catch { return }
        }
        defer { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) } }
        let now = Date()
        if let cacheURL, let data = readCache(cacheURL), data.count <= 8192,
           let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.schemaVersion == 1,
           cache.source == Self.endpoint.absoluteString, cache.installedVersion == currentVersion, cache.hasStableVersion,
           now.timeIntervalSince(cache.checkedAt) >= 0, now.timeIntervalSince(cache.checkedAt) < 86400 {
            setNotice(cache.latestVersion)
            return
        }
        let latest = try? check().latestVersion
        setNotice(latest)
        if let cacheURL {
            let cache = Cache(schemaVersion: 1, source: Self.endpoint.absoluteString, installedVersion: currentVersion, checkedAt: now, latestVersion: latest)
            if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        }
    }

    private func setNotice(_ latest: String?) {
        let checked = latest.flatMap { try? result(for: $0) }
        noticeLock.lock(); defer { noticeLock.unlock() }
        storedNotice = checked?.isUpdateAvailable == true ? "Yeni sürüm · tawl update · v\(checked!.latestVersion)" : nil
    }

    static func actualExecutableURL() -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return URL(fileURLWithPath: "/unknown/tawl") }
        return URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL
    }
}
