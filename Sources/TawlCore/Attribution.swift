import Foundation

public struct ProcessIdentity {
    public var applicationID: String
    public var applicationName: String
    public var projectID: String?
    public var projectName: String?
    public var projectEvidence: String?
}

// Stable local pseudonym, not an anonymization guarantee.
private func identityHash(_ text: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
    return String(hash, radix: 16)
}

public final class Attributor {
    private struct CachedProject { var checked: Date; var root: String? }
    private var projects: [String: CachedProject] = [:]
    public init() {}

    private func application(_ path: String?) -> (String, String)? {
        guard let path, let range = path.range(of: ".app/", options: [.caseInsensitive]) else { return nil }
        let root = String(path[..<range.upperBound].dropLast())
        return ("app:" + identityHash(root), cleanText(URL(fileURLWithPath: root).deletingPathExtension().lastPathComponent))
    }
    private func projectRoot(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/"), path.utf8.count <= 4096 else { return nil }
        if let cached = projects[path], Date().timeIntervalSince(cached.checked) < 30 { return cached.root }
        var url = URL(fileURLWithPath: path).standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: String?
        for _ in 0..<12 {
            if url.path == "/" || url.path == home { break }
            if !url.pathComponents.contains("node_modules") && !url.pathComponents.contains(".build") {
                let markers = [".git", "package.json", "Package.swift", "pyproject.toml", "go.mod", "Cargo.toml"]
                if markers.contains(where: { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }) {
                    found = url.path; break
                }
            }
            url.deleteLastPathComponent()
        }
        if projects.count >= 4096 { projects.removeAll(keepingCapacity: true) }
        projects[path] = CachedProject(checked: Date(), root: found)
        return found
    }
    public func identify(_ process: RawProcess, among processes: [RawProcess]) -> ProcessIdentity {
        var app = application(process.executablePath)
        // Attribute spawned workers to a visible app only through a live parent chain.
        if app == nil {
            var current = process; var visited: Set<Int32> = [process.pid]
            for _ in 0..<12 {
                guard current.parentPID > 1, !visited.contains(current.parentPID),
                      let parent = processes.first(where: { $0.pid == current.parentPID }),
                      parent.startedAt <= current.startedAt else { break }
                visited.insert(parent.pid)
                if let parentApp = application(parent.executablePath) { app = parentApp; break }
                current = parent
            }
        }
        let executable = process.executablePath
        var result = ProcessIdentity(
            applicationID: app?.0 ?? executable.map { "exe:" + identityHash($0) } ?? "process:" + process.id,
            applicationName: app?.1 ?? cleanText(process.name))
        if let root = projectRoot(process.workingDirectory) {
            result.projectID = "project:" + identityHash(root)
            result.projectName = cleanText(URL(fileURLWithPath: root).lastPathComponent)
            result.projectEvidence = "Çalışma dizini + proje işareti"
        }
        return result
    }
}

public func groupProcesses(_ snapshot: Snapshot, by grouping: Grouping) -> [Workload] {
    let unique = Dictionary(snapshot.processes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let groups = Dictionary(grouping: unique.values) { p in
        workloadGroupIdentity(for: p, by: grouping).id
    }
    let workloads = groups.map { id, members -> Workload in
        let cpu = members.compactMap(\.cpuCores)
        let memory = members.compactMap(\.footprintBytes)
        let deltas = members.compactMap(\.memoryDeltaBytes)
        return Workload(id: id,
                        name: workloadGroupIdentity(for: members.min(by: { $0.id < $1.id })!, by: grouping).name,
                        memberIDs: members.map(\.id).sorted(),
                        cpuCores: cpu.isEmpty ? nil : cpu.reduce(0,+),
                        footprintBytes: memory.isEmpty ? nil : memory.reduce(0) { sum, value in
                            let (next, overflow) = sum.addingReportingOverflow(value); return overflow ? UInt64.max : next
                        },
                        memoryDeltaBytes: deltas.isEmpty ? nil : deltas.reduce(0) { sum, value in
                            let (next, overflow) = sum.addingReportingOverflow(value); return overflow ? (value > 0 ? Int64.max : Int64.min) : next
                        },
                        unknownCPUCount: members.count-cpu.count, unknownMemoryCount: members.count-memory.count)
    }
    return workloads.sorted { a,b in
        if snapshot.pressure == .warning || snapshot.pressure == .critical {
            if a.footprintBytes != b.footprintBytes { return (a.footprintBytes ?? 0) > (b.footprintBytes ?? 0) }
        } else if a.cpuCores != b.cpuCores { return (a.cpuCores ?? -1) > (b.cpuCores ?? -1) }
        return a.id < b.id
    }
}
