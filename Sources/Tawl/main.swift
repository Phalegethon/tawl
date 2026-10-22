import Foundation
import Darwin
import TawlCore

private var interrupted: Int32 = 0
private func stderrLine(_ text: String) { FileHandle.standardError.write(Data((cleanText(text) + "\n").utf8)) }

private var help: String { L10n.text("""
TAWL — Terminal Activity & Workload Lens
Understand macOS resource usage by application, project and usage category.

  tawl                                  Live terminal monitor (watch)
  tawl --lang en|tr                      Language (default: en)
  tawl --version                        Installed version
  tawl update check                     Check for a newer release (--check also works)
  tawl update                           Confirm and update (--yes: unattended)
  tawl --no-update-check                 Disable automatic update checks
  tawl status --sample 3s                Short resource report
  tawl status --json                     Same measurements as JSON
  tawl watch --record session.tawl       Live monitor with explicit recording
  tawl record --duration 10m --output session.tawl
  tawl report session.tawl --last 5m      Inspect a recording offline
  tawl report session.tawl --json

Live monitor: Tab grouping · ↑↓/jk select · Enter details · / search
h history · m mark · Space freeze display · ? help · q quit

CPU cores = core equivalents; 1.00 = one logical core.
Memory = process physical footprint totals; missing coverage is shown separately.
GPU: per-device load where exposed by the driver; per-core GPU load is unavailable.
Temperature and disk latency are not measured. High swap alone is not a bottleneck.
Recording is opt-in, never overwrites a file, and is limited to 100 MiB.
Update checks run in the background at most once daily; measurements are not sent.
TAWL_NO_UPDATE_CHECK=1 disables automatic checks. Updates never install automatically.
Language: --lang en|tr overrides TAWL_LANG; otherwise English is used.
""") }

private struct Report: Encodable {
    let schemaVersion = 1
    var snapshots: [Snapshot]
    var findings: [Finding]
    var markers: [EventMarker]
    var warnings: [String]
}
private func printReport(_ samples: [Snapshot], markers: [EventMarker] = [], warnings: [String] = [], json: Bool) throws {
    guard !samples.isEmpty else { throw CLIError(L10n.text("No completed samples in the selected time window.")) }
    let findings = analyzeSession(samples)
    if json {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Report(snapshots: samples, findings: findings, markers: markers, warnings: warnings))
        FileHandle.standardOutput.write(data); print(); return
    }
    guard let s = samples.last else { throw CLIError(L10n.text("No completed samples in the selected time window.")) }
    let date = ISO8601DateFormatter()
    print("TAWL  |  \(date.string(from: s.timestamp))")
    print(L10n.text("\(samples.count) samples · \(date.string(from: samples.first!.timestamp)) → \(date.string(from: s.timestamp))"))
    let cpu = s.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    print(L10n.text("CPU \(cpu) / \(s.logicalCPUCount) logical cores   Memory pressure: \(pressureLabel(s.pressure))"))
    print(L10n.text("RAM capacity \(formatBytes(s.memoryTotalBytes == 0 ? nil : s.memoryTotalBytes)) · Compressed \(formatBytes(s.compressedBytes))"))
    print(L10n.text("Swap \(formatBytes(s.swapUsedBytes)) · in \(formatRate(s.swapInBytesPerSecond)) · out \(formatRate(s.swapOutBytesPerSecond))"))
    print(L10n.text("Disk read/write \(formatRate(s.diskReadBytesPerSecond)) / \(formatRate(s.diskWriteBytesPerSecond))"))
    print(L10n.text("Network receive/send \(formatRate(s.networkInBytesPerSecond)) / \(formatRate(s.networkOutBytesPerSecond))"))
    print(L10n.text("Visible processes \(s.processes.count)/\(s.totalProcessCount) · unreadable identities \(s.unreadableProcessCount)"))
    print(L10n.text("\nTOP APPLICATIONS IN LAST SAMPLE  (cores = core equivalents)"))
    for group in groupProcesses(s, by: .application).prefix(10) {
        let cpu = group.cpuCores.map { String(format: "%.2f", $0) } ?? "—"
        let missing = (group.unknownCPUCount > 0 || group.unknownMemoryCount > 0) ? L10n.text(" [partial]") : ""
        print(L10n.text("  \(cleanText(group.name)) · \(cpu) cores · \(formatBytes(group.footprintBytes)) · \(group.memberIDs.count) processes\(missing)"))
    }
    print(L10n.text("\nFINDINGS"))
    for f in findings { print("  [\(date.string(from: f.start)) → \(date.string(from: f.end))] \(cleanText(f.title)): \(cleanText(f.detail))") }
    if let first = samples.first, samples.count > 1 {
        let before = Dictionary(groupProcesses(first, by: .application).map { ($0.id,$0) }, uniquingKeysWith: { a,_ in a })
        let growth = groupProcesses(s, by: .application).compactMap { group -> (String,UInt64)? in
            guard group.unknownMemoryCount == 0, let prior = before[group.id], prior.unknownMemoryCount == 0,
                  Set(group.memberIDs) == Set(prior.memberIDs), let now = group.footprintBytes, let old = prior.footprintBytes, now > old else { return nil }
            return (group.name,now-old)
        }.sorted { $0.1 > $1.1 }.prefix(3)
        if !growth.isEmpty {
            print(L10n.text("\nWHAT CHANGED?  (same processes, first and last sample)"))
            for (name,bytes) in growth { print(L10n.text("  \(cleanText(name)): +\(formatBytes(bytes)) memory; this does not diagnose a leak.")) }
        }
    }
    if !markers.isEmpty {
        print(L10n.text("\nMARKERS"))
        for marker in markers { print("  \(date.string(from: marker.timestamp)) · \(cleanText(marker.label))") }
    }
    let limits = Array(Set(s.limitations + warnings)).sorted()
    if !limits.isEmpty { print(L10n.text("\nCOVERAGE")); for limit in limits { print("  \(cleanText(limit))") } }
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    L10n.configure(try CLIOptions.languageSelection(arguments).language)
    let options = try CLIOptions.parse(arguments)
    if options.help { print(help); return }
    if options.command == "version" { print("tawl \(BuildInfo.version)"); return }
    if options.command == "update" || options.command == "update-check" {
        let updates = UpdateService()
        let result = try updates.check()
        print(cleanText(result.message))
        guard options.command == "update", result.isUpdateAvailable else { return }
        if !options.assumeYes {
            guard isatty(STDIN_FILENO) != 0 else { throw CLIError(L10n.text("Confirmation requires an interactive terminal; unattended update: tawl update --yes")) }
            stderrLine(L10n.text("Update TAWL \(BuildInfo.version) → \(result.latestVersion)? [y/N]"))
            guard let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), ["y", "yes", L10n.string("y"), L10n.string("yes")].contains(response) else {
                print(L10n.text("Update cancelled.")); return
            }
        }
        print(cleanText(try updates.apply(expectedVersion: result.latestVersion))); return
    }
    if options.command == "report" {
        let recording = try RecordingReader.read(url: URL(fileURLWithPath: options.input!))
        let samples = reportWindow(recording.snapshots, lastSeconds: options.lastSeconds)
        var warnings = recording.warnings
        let clockAdjusted = zip(recording.snapshots, recording.snapshots.dropFirst()).contains { first, next in
            abs(next.timestamp.timeIntervalSince(first.timestamp) - (next.monotonicTime-first.monotonicTime)) > 2
        }
        if clockAdjusted { warnings.append(L10n.text("System clock changed: the time window uses monotonic time; wall-clock timestamps may jump.")) }
        var markers = recording.markers
        if options.lastSeconds != nil, let first = samples.first {
            if clockAdjusted {
                warnings.append(L10n.text("System clock changed: markers cannot be matched precisely to the time window; showing all markers in the file."))
            } else {
                // Keep marks after the final sample too: pressing m then q is a valid recording.
                markers = markers.filter { $0.timestamp >= first.timestamp }
            }
        }
        try printReport(samples, markers: markers, warnings: warnings, json: options.json); return
    }
    let collector = NativeCollector(); let reducer = SnapshotReducer()
    func next() -> Snapshot { reducer.reduce(collector.collect()) }
    if options.command == "status" {
        let first = next(); Thread.sleep(forTimeInterval: options.sampleSeconds)
        try printReport([first,next()], json: options.json); return
    }
    if options.command == "watch", (isatty(STDIN_FILENO) == 0 || isatty(STDOUT_FILENO) == 0) {
        throw CLIError(L10n.text("Live view requires an interactive terminal. Use tawl status or record."))
    }
    let writer = try options.output.map { try RecordingWriter(url: URL(fileURLWithPath: $0)) }
    defer { try? writer?.close() }
    if options.command == "watch" {
        let updates = UpdateService()
        if !options.noUpdateCheck { updates.startAutomaticCheck() }
        try TerminalUI().run(nextSnapshot: next, onSnapshot: { try writer?.append($0) }, onMarker: { try writer?.appendMarker($0) }, recordingActive: writer != nil, updateNotice: { options.noUpdateCheck ? nil : updates.notice })
        try writer?.close()
    } else {
        let priorINT = signal(SIGINT) { _ in interrupted = 1 }
        let priorTERM = signal(SIGTERM) { _ in interrupted = 1 }
        defer { signal(SIGINT,priorINT); signal(SIGTERM,priorTERM) }
        let start = ProcessInfo.processInfo.systemUptime
        let end = start + options.durationSeconds
        var count = 0
        stderrLine(L10n.text("Recording started; press Ctrl-C to finish. Recorded names may contain sensitive information."))
        while interrupted == 0 {
            try writer?.append(next()); count += 1
            if ProcessInfo.processInfo.systemUptime >= end { break }
            let deadline = min(end, ProcessInfo.processInfo.systemUptime + 2)
            while interrupted == 0 && ProcessInfo.processInfo.systemUptime < deadline { usleep(50_000) }
        }
        try writer?.close()
        stderrLine(L10n.text("Recording complete: \(count) samples."))
    }
}
do { try run() }
catch {
    let message = (error as? CLIError)?.description ?? error.localizedDescription
    stderrLine("tawl: " + message); exit(1)
}
