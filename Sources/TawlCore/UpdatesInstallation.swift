import Foundation
import CryptoKit
import Darwin

private struct UpdateHomebrewInfo: Decodable {
    struct Formula: Decodable {
        struct Versions: Decodable { let stable: String }
        let full_name: String
        let versions: Versions
    }
    let formulae: [Formula]
}

extension UpdateService {
    public func apply(expectedVersion: String? = nil) throws -> String {
        let resolved = executableURL.resolvingSymlinksInPath()
        if resolved.path.contains("/Cellar/tawl/") {
            let derived = resolved.path.components(separatedBy: "/Cellar/tawl/")[0] + "/bin/brew"
            let brew = homebrewURL ?? URL(fileURLWithPath: derived)
            guard FileManager.default.isExecutableFile(atPath: brew.path) else {
                throw UpdateError("Homebrew installation detected. Run `brew update && brew upgrade phalegethon/tawl/tawl` from your shell.")
            }
            let refresh = try runner(brew, ["update"], 600)
            guard refresh.status == 0 else { throw UpdateError("Homebrew update failed: \(refresh.output.prefix(2000))") }
            let formulaInfo = try runner(brew, ["info", "--json=v2", "phalegethon/tawl/tawl"], 30)
            guard formulaInfo.status == 0,
                  let info = try? JSONDecoder().decode(UpdateHomebrewInfo.self, from: Data(formulaInfo.output.utf8)),
                  info.formulae.count == 1, let formula = info.formulae.first,
                  formula.full_name == "phalegethon/tawl/tawl",
                  let candidateVersion = try? SemanticVersion(formula.versions.stable), candidateVersion.prerelease.isEmpty else {
                throw UpdateError("Homebrew formula version could not be verified. Nothing was installed; inspect `brew info phalegethon/tawl/tawl` before retrying.")
            }
            let candidate = formula.versions.stable
            if let expectedVersion, candidate != expectedVersion {
                throw UpdateError("Homebrew formula is \(candidate), but you confirmed \(expectedVersion). Nothing was installed; run `tawl update` again after the release and tap agree.")
            }
            guard candidateVersion > (try SemanticVersion(currentVersion)) else {
                throw UpdateError("Homebrew has no newer stable TAWL version than \(currentVersion). Nothing was installed.")
            }
            let upgrade = try runner(URL(fileURLWithPath: "/usr/bin/env"), ["HOMEBREW_NO_AUTO_UPDATE=1", brew.path, "upgrade", "phalegethon/tawl/tawl"], 600)
            guard upgrade.status == 0 else { throw UpdateError("Homebrew upgrade failed: \(upgrade.output.prefix(2000))") }
            let binary = URL(fileURLWithPath: derived).deletingLastPathComponent().appendingPathComponent("tawl")
            let reported = try runner(binary, ["--version"], 5)
            let words = reported.output.split(whereSeparator: { $0.isWhitespace })
            guard reported.status == 0, words.count == 2, words[0] == "tawl",
                  let installed = try? SemanticVersion(String(words[1])), installed.prerelease.isEmpty else {
                throw UpdateError("Homebrew finished, but the installed TAWL version could not be verified. Run `tawl --version` and inspect Homebrew before retrying.")
            }
            let actual = String(words[1])
            guard installed > (try SemanticVersion(currentVersion)), actual == candidate else {
                throw UpdateError("Homebrew reports TAWL \(actual); expected \(candidate). Inspect `brew info phalegethon/tawl/tawl` before retrying the upgrade.")
            }
            return "Homebrew installed TAWL \(actual). Restart TAWL to use the new version."
        }
        let original = try standaloneIdentity()
        let release = try fetchRelease()
        if let expectedVersion, release.version != expectedVersion {
            throw UpdateError("Latest release changed from \(expectedVersion) to \(release.version). Nothing was installed; run `tawl update` again to review the new version.")
        }
        guard try release.validatedVersion() > SemanticVersion(currentVersion) else {
            throw UpdateError("No newer stable release is available; TAWL \(currentVersion) was left unchanged.")
        }
        guard ["arm64", "x86_64"].contains(architecture) else { throw UpdateError("Unsupported update architecture.") }
        let assetName = "tawl-\(release.version)-macos-\(architecture)"
        let candidates = release.assets.filter { $0.name == assetName }
        guard candidates.count == 1, let asset = candidates.first else { throw UpdateError("Release has no unique \(assetName) binary. Install manually from https://github.com/\(BuildInfo.repository)/releases.") }
        let expectedURL = "https://github.com/\(BuildInfo.repository)/releases/download/\(release.tag_name)/\(assetName)"
        guard asset.browser_download_url == expectedURL, let url = URL(string: expectedURL),
              url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, asset.size > 0, asset.size <= Self.maximumBinarySize else {
            throw UpdateError("Release asset URL or size failed validation.")
        }
        guard let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              digest.dropFirst(7).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw UpdateError("GitHub has not supplied a valid SHA-256 digest for this binary. Install manually after verification.")
        }
        let payload = try transport(url, Self.maximumBinarySize)
        guard payload.count == asset.size, payload.count <= Self.maximumBinarySize,
              Self.sha256(payload) == String(digest.dropFirst(7)) else { throw UpdateError("Downloaded binary failed SHA-256 or size verification. Installation is unchanged.") }
        try Self.validateMachO(payload, architecture: architecture)
        try replaceStandalone(payload: payload, expectedVersion: release.version, original: original)
        return "Updated TAWL \(currentVersion) → \(release.version). Restart TAWL to use the new version."
    }

    private func standaloneIdentity() throws -> stat {
        struct Receipt: Decodable {
            let schemaVersion: Int
            let method: String
            let repository: String
        }
        let guidance = "Self-update requires a standalone installation with its receipt. Reinstall with the official installer, or use Homebrew. See https://github.com/\(BuildInfo.repository)#installation."
        guard executableURL.lastPathComponent == "tawl", executableURL.deletingLastPathComponent().lastPathComponent == "bin",
              executableURL == executableURL.resolvingSymlinksInPath() else { throw UpdateError(guidance) }
        var target = stat()
        guard lstat(executableURL.path, &target) == 0, (target.st_mode & S_IFMT) == S_IFREG,
              target.st_uid == getuid(), target.st_mode & 0o222 != 0,
              access(executableURL.path, W_OK) == 0,
              access(executableURL.deletingLastPathComponent().path, W_OK) == 0 else {
            throw UpdateError("Installed binary must be a writable regular file owned by your user. \(guidance)")
        }
        let receipt = executableURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/tawl/install.json")
        guard receipt == receipt.resolvingSymlinksInPath() else { throw UpdateError("Refusing a symlinked installation receipt. \(guidance)") }
        let fd = open(receipt.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw UpdateError(guidance) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(),
              info.st_size > 0, info.st_size <= 4096,
              let data = try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: 4097),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.schemaVersion == 1, receipt.method == "standalone",
              receipt.repository == BuildInfo.repository else { throw UpdateError(guidance) }
        return target
    }

    private func replaceStandalone(payload: Data, expectedVersion: String, original: stat) throws {
        let parent = executableURL.deletingLastPathComponent()
        let dirFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dirFD >= 0 else { throw UpdateError("Cannot safely open the installation directory.") }
        defer { close(dirFD) }
        let temporaryName = ".tawl-update-\(UUID().uuidString)"
        let temporaryURL = parent.appendingPathComponent(temporaryName)
        let fd = openat(dirFD, temporaryName, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o700)
        guard fd >= 0 else { throw UpdateError("Cannot create a temporary binary beside the installation.") }
        defer { close(fd); unlinkat(dirFD, temporaryName, 0) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.write(contentsOf: payload)
        guard fchmod(fd, 0o755) == 0, fsync(fd) == 0 else { throw UpdateError("Could not prepare the update binary.") }
        let version = try runner(temporaryURL, ["--version"], 5)
        guard version.status == 0, version.output.trimmingCharacters(in: .whitespacesAndNewlines) == "tawl \(expectedVersion)" else {
            throw UpdateError("Downloaded binary did not report the expected TAWL version. Installation is unchanged.")
        }
        // Re-read the staged file after execution and recheck target identity before the atomic rename.
        let stagedFD = openat(dirFD, temporaryName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard stagedFD >= 0 else { throw UpdateError("Staged update disappeared. Installation is unchanged.") }
        defer { close(stagedFD) }
        var stagedInfo = stat()
        guard fstat(stagedFD, &stagedInfo) == 0, stagedInfo.st_size == payload.count,
              let staged = try FileHandle(fileDescriptor: stagedFD, closeOnDealloc: false).read(upToCount: payload.count + 1),
              Self.sha256(staged) == Self.sha256(payload) else { throw UpdateError("Staged update changed during verification. Installation is unchanged.") }
        let current = try standaloneIdentity()
        var anchored = stat()
        guard current.st_ino == original.st_ino, current.st_dev == original.st_dev,
              fstatat(dirFD, "tawl", &anchored, AT_SYMLINK_NOFOLLOW) == 0,
              anchored.st_ino == original.st_ino, anchored.st_dev == original.st_dev else {
            throw UpdateError("Installation changed while checking the update. Retry after other installers finish.")
        }
        guard renameat(dirFD, temporaryName, dirFD, "tawl") == 0 else { throw UpdateError("Could not replace the installed binary. Installation is unchanged.") }
        _ = fsync(dirFD)
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func validateMachO(_ data: Data, architecture: String) throws {
        let bytes = [UInt8](data.prefix(32))
        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard bytes.count == 32, word(0) == 0xfeedfacf,
              word(4) == (architecture == "arm64" ? 0x0100000c : 0x01000007), word(12) == 2,
              UInt64(word(20)) <= UInt64(data.count - 32), word(16) > 0, word(16) <= word(20) / 8 else {
            throw UpdateError("Downloaded file is not a compatible \(architecture) Mach-O executable. Installation is unchanged.")
        }
        let commandEnd = 32 + Int(word(20))
        var offset = 32
        for _ in 0..<word(16) {
            guard offset <= commandEnd - 8 else { throw UpdateError("Truncated Mach-O load commands.") }
            let size = Int(UInt32(data[offset + 4]) | UInt32(data[offset + 5]) << 8 |
                           UInt32(data[offset + 6]) << 16 | UInt32(data[offset + 7]) << 24)
            guard size >= 8, size % 8 == 0, size <= commandEnd - offset else { throw UpdateError("Invalid Mach-O load command size.") }
            offset += size
        }
        guard offset == commandEnd else { throw UpdateError("Mach-O load command length mismatch.") }
    }
}
