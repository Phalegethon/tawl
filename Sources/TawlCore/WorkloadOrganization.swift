import Foundation

public enum WorkloadSort: String, CaseIterable, Sendable {
    case automatic, name, cpu, footprint, memoryDelta, members

    public var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .name: return "İş yükü"
        case .cpu: return "CPU"
        case .footprint: return "Ayak izi"
        case .memoryDelta: return "Δ Bellek"
        case .members: return "Üye"
        }
    }
}

public enum SortDirection: String, CaseIterable, Sendable {
    case ascending, descending
    public var symbol: String { self == .ascending ? "↑" : "↓" }
}

extension Grouping {
    public var title: String {
        switch self {
        case .application: return "Uygulamalar"
        case .project: return "Projeler"
        case .category: return "Kullanım alanları"
        }
    }
}

public enum UsageCategory: String, CaseIterable, Sendable {
    case browsers, development, ai, communication, virtualization, databases, media, system, other

    public var title: String {
        switch self {
        case .browsers: return "Tarayıcılar"
        case .development: return "Geliştirme"
        case .ai: return "Yapay zekâ"
        case .communication: return "İletişim"
        case .virtualization: return "Sanallaştırma"
        case .databases: return "Veritabanları"
        case .media: return "Medya"
        case .system: return "Sistem"
        case .other: return "Diğer"
        }
    }
}

private enum UsageRules {
    static let families: [(UsageCategory, [String])] = [
            (.browsers, ["safari", "google chrome", "chromium", "firefox", "microsoft edge", "brave browser", "arc", "dia", "orion"]),
            (.development, ["visual studio code", "code", "code - insiders", "cursor", "xcode", "zed", "webstorm", "intellij idea", "pycharm", "terminal", "iterm2", "iterm", "warp", "alacritty", "wezterm", "ghostty", "git", "node", "nodejs", "npm", "pnpm", "yarn", "deno", "bun", "swift", "swift-frontend", "clang", "clang++", "rustc", "cargo", "go", "python", "python3", "ruby", "java", "gradle", "dotnet"]),
            (.ai, ["claude", "chatgpt", "codex", "codex computer use", "ollama", "lm studio", "t3 code", "t3 code (beta)"]),
            (.communication, ["slack", "discord", "microsoft teams", "teams", "zoom", "zoom.us", "whatsapp", "telegram", "messages", "mail", "facetime", "gatherv2", "gather"]),
            (.virtualization, ["docker", "docker desktop", "com.docker.backend", "colima", "lima", "orbstack", "parallels desktop", "vmware fusion", "virtualbox", "utm"]),
            (.databases, ["postgres", "postgresql", "postmaster", "mysqld", "mariadbd", "redis-server", "mongod", "mongos", "pgadmin 4", "tableplus", "dbeaver", "datagrip"]),
            (.media, ["music", "spotify", "vlc", "quicktime player", "photos", "final cut pro", "logic pro", "garageband", "obs", "obs studio", "davinci resolve"]),
            (.system, ["kernel_task", "launchd", "windowserver", "loginwindow", "finder", "dock", "systemuiserver", "controlcenter", "windowmanager", "spotlight", "mds", "mds_stores", "mdworker", "mdworker_shared", "runningboardd", "powerd", "coreaudiod", "corebrightnessd", "corespeechd", "cfprefsd", "distnoted", "notifyd", "syslogd", "logd", "watchdogd", "tccd", "trustd", "securityd", "opendirectoryd", "sharingd", "fileproviderd", "bird", "cloudd", "nsurlsessiond", "softwareupdated", "networkserviceproxy", "rapportd", "screencapture", "screencaptureui", "activity monitor"])
        ]
    static let names: [String: UsageCategory] = Dictionary(uniqueKeysWithValues: families.flatMap { category, names in names.map { ($0, category) } })
    static let bundles: [(String, UsageCategory)] = [
            ("com.apple.safari", .browsers), ("com.google.chrome", .browsers),
            ("org.mozilla.firefox", .browsers), ("com.microsoft.edgemac", .browsers),
            ("com.microsoft.vscode", .development), ("com.apple.dt.xcode", .development),
            ("com.anthropic.claudefordesktop", .ai), ("com.openai.chat", .ai),
            ("com.tinyspeck.slackmacgap", .communication), ("com.hnc.discord", .communication),
            ("com.apple.appkit.xpc", .system), ("com.apple.webkit.networking", .system)
        ]
}

/// Usage labels describe a known app family, not what the user is doing in it.
/// Exact names plus explicit helper suffixes avoid classifying arbitrary lookalikes.
public func usageCategory(for process: ProcessSample) -> UsageCategory {
    func family(_ value: String) -> UsageCategory? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = UsageRules.names[name] { return exact }
        for marker in [" helper", " (renderer)", " (service)"] {
            if let range = name.range(of: marker), let match = UsageRules.names[String(name[..<range.lowerBound])] { return match }
        }
        if name.hasPrefix("com.apple.virtualization.") || name.hasPrefix("qemu-system-") { return .virtualization }
        if name.hasPrefix("python3."), !name.dropFirst(8).isEmpty, name.dropFirst(8).allSatisfy({ $0.isNumber || $0 == "." }) { return .development }
        for (bundle, category) in UsageRules.bundles where name == bundle || name.hasPrefix(bundle + ".") { return category }
        return nil
    }
    // Keep the full app family together. An unknown app's node worker is not evidence
    // that the app is a development tool; bare executables may use the process name.
    if let category = family(process.applicationName) ?? family(process.applicationID) { return category }
    return process.applicationID.hasPrefix("app:") ? .other : (family(process.name) ?? .other)
}

public func workloadGroupIdentity(for process: ProcessSample, by grouping: Grouping) -> (id: String, name: String) {
    switch grouping {
    case .application: return (process.applicationID, process.applicationName)
    case .project: return (process.projectID ?? "unassigned", process.projectName ?? "Projesi belirlenemeyen")
    case .category:
        let category = usageCategory(for: process)
        return ("category:" + category.rawValue, category.title)
    }
}

/// nil sorts after every measured value in both directions; ties retain stable identity order.
private func ordered<Value: Comparable>(_ left: Value?, _ right: Value?, direction: SortDirection, leftID: String, rightID: String) -> Bool {
    switch (left, right) {
    case (.none, .some): return false
    case (.some, .none): return true
    case let (.some(a), .some(b)) where a != b: return direction == .ascending ? a < b : a > b
    default: return leftID < rightID
    }
}

private func nameOrdered(_ left: String, _ right: String, direction: SortDirection, leftID: String, rightID: String) -> Bool {
    let comparison = left.compare(right, options: [.caseInsensitive, .numeric], locale: Locale(identifier: "tr_TR"))
    if comparison == .orderedSame { return leftID < rightID }
    return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
}

public func sortedWorkloads(_ workloads: [Workload], sort: WorkloadSort, direction: SortDirection, snapshot: Snapshot) -> [Workload] {
    let key: WorkloadSort = sort == .automatic ? ((snapshot.pressure == .warning || snapshot.pressure == .critical) ? .footprint : .cpu) : sort
    return workloads.sorted { a, b in
        switch key {
        case .name: return nameOrdered(a.name, b.name, direction: direction, leftID: a.id, rightID: b.id)
        case .cpu, .automatic: return ordered(a.cpuCores.flatMap { $0.isFinite ? $0 : nil }, b.cpuCores.flatMap { $0.isFinite ? $0 : nil }, direction: direction, leftID: a.id, rightID: b.id)
        case .footprint: return ordered(a.footprintBytes, b.footprintBytes, direction: direction, leftID: a.id, rightID: b.id)
        case .memoryDelta: return ordered(a.memoryDeltaBytes, b.memoryDeltaBytes, direction: direction, leftID: a.id, rightID: b.id)
        case .members: return ordered(a.memberIDs.count, b.memberIDs.count, direction: direction, leftID: a.id, rightID: b.id)
        }
    }
}

public func sortedProcesses(_ processes: [ProcessSample], sort: WorkloadSort, direction: SortDirection) -> [ProcessSample] {
    processes.sorted { a, b in
        switch sort {
        case .name: return nameOrdered(a.name, b.name, direction: direction, leftID: a.id, rightID: b.id)
        case .cpu, .automatic: return ordered(a.cpuCores.flatMap { $0.isFinite ? $0 : nil }, b.cpuCores.flatMap { $0.isFinite ? $0 : nil }, direction: direction, leftID: a.id, rightID: b.id)
        case .footprint: return ordered(a.footprintBytes, b.footprintBytes, direction: direction, leftID: a.id, rightID: b.id)
        case .memoryDelta: return ordered(a.memoryDeltaBytes, b.memoryDeltaBytes, direction: direction, leftID: a.id, rightID: b.id)
        case .members: return a.id < b.id // Each row is one process.
        }
    }
}
