import Foundation
import Darwin
import TawlCore

private var interrupted: Int32 = 0
private func stderrLine(_ text: String) { FileHandle.standardError.write(Data((cleanText(text) + "\n").utf8)) }

private let help = """
TAWL — Terminal Activity & Workload Lens
macOS sistem yükünü uygulama, proje ve kullanım alanı düzeyinde okuyun.

  tawl                                 Canlı terminal (watch)
  tawl --version                       Kurulu sürüm
  tawl update check                    Yeni sürüm kontrolü (--check de olur)
  tawl update                          Onayla ve güncelle (--yes: doğrudan)
  tawl --no-update-check               Otomatik sürüm kontrolünü kapat
  tawl status --sample 3s              Kısa ölçüm raporu
  tawl status --json                   Aynı ölçüm, JSON
  tawl watch --record oturum.tawl       Canlı ekran + açık kayıt
  tawl record --duration 10m --output oturum.tawl
  tawl report oturum.tawl --last 5m     Kaydı çevrimdışı incele
  tawl report oturum.tawl --json

Canlı ekran: Tab gruplama · ↑↓/jk seçim · Enter detay · / ara
h geçmiş · m işaret · Space ekranı dondur · ? yardım · q çıkış

CPU çek. = kullanılan çekirdek eşdeğeri; 1.00 = bir mantıksal çekirdek.
Bellek = süreç physical footprint toplamı; eksik kapsam ayrıca gösterilir.
GPU: sürücü sunarsa aygıt toplamı ölçülür; çekirdek başına GPU kullanımı yoktur.
Isı ve disk gecikmesi ölçülmez. Büyük swap tek başına darboğaz değildir.
Kayıt açıkça istenir, mevcut dosya üzerine yazılmaz; dosya sınırı 100 MiB.
Sürüm kontrolü: arka planda, günde en çok bir kez; ölçüm verileri gönderilmez.
TAWL_NO_UPDATE_CHECK=1 otomatik kontrolü kapatır. Güncelleme otomatik kurulmaz.
"""

private struct Report: Encodable {
    let schemaVersion = 1
    var snapshots: [Snapshot]
    var findings: [Finding]
    var markers: [EventMarker]
    var warnings: [String]
}
private func printReport(_ samples: [Snapshot], markers: [EventMarker] = [], warnings: [String] = [], json: Bool) throws {
    guard !samples.isEmpty else { throw CLIError("Seçili zaman aralığında tamamlanmış ölçüm yok.") }
    let findings = analyzeSession(samples)
    if json {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Report(snapshots: samples, findings: findings, markers: markers, warnings: warnings))
        FileHandle.standardOutput.write(data); print(); return
    }
    guard let s = samples.last else { throw CLIError("Seçili zaman aralığında tamamlanmış ölçüm yok.") }
    let date = ISO8601DateFormatter()
    print("TAWL  |  \(date.string(from: s.timestamp))")
    print("\(samples.count) örnek · \(date.string(from: samples.first!.timestamp)) → \(date.string(from: s.timestamp))")
    let cpu = s.cpuPercent.map { String(format: "%%%.1f", $0) } ?? "—"
    print("CPU \(cpu) / \(s.logicalCPUCount) mantıksal çekirdek   Bellek baskısı: \(pressureLabel(s.pressure))")
    print("RAM kapasitesi \(formatBytes(s.memoryTotalBytes == 0 ? nil : s.memoryTotalBytes)) · Sıkıştırılmış \(formatBytes(s.compressedBytes))")
    print("Swap \(formatBytes(s.swapUsedBytes)) · giriş \(formatRate(s.swapInBytesPerSecond)) · çıkış \(formatRate(s.swapOutBytesPerSecond))")
    print("Disk okuma/yazma \(formatRate(s.diskReadBytesPerSecond)) / \(formatRate(s.diskWriteBytesPerSecond))")
    print("Ağ alım/gönderim \(formatRate(s.networkInBytesPerSecond)) / \(formatRate(s.networkOutBytesPerSecond))")
    print("Görünen süreç \(s.processes.count)/\(s.totalProcessCount) · kimliği okunamayan \(s.unreadableProcessCount)")
    print("\nSON ÖRNEKTE ÖNE ÇIKAN UYGULAMALAR  (çek. = çekirdek eşdeğeri)")
    for group in groupProcesses(s, by: .application).prefix(10) {
        let cpu = group.cpuCores.map { String(format: "%.2f", $0) } ?? "—"
        let missing = (group.unknownCPUCount > 0 || group.unknownMemoryCount > 0) ? " [kısmi]" : ""
        print("  \(cleanText(group.name)) · \(cpu) çek. · \(formatBytes(group.footprintBytes)) · \(group.memberIDs.count) süreç\(missing)")
    }
    print("\nYORUM")
    for f in findings { print("  [\(date.string(from: f.start)) → \(date.string(from: f.end))] \(cleanText(f.title)): \(cleanText(f.detail))") }
    if let first = samples.first, samples.count > 1 {
        let before = Dictionary(groupProcesses(first, by: .application).map { ($0.id,$0) }, uniquingKeysWith: { a,_ in a })
        let growth = groupProcesses(s, by: .application).compactMap { group -> (String,UInt64)? in
            guard group.unknownMemoryCount == 0, let prior = before[group.id], prior.unknownMemoryCount == 0,
                  Set(group.memberIDs) == Set(prior.memberIDs), let now = group.footprintBytes, let old = prior.footprintBytes, now > old else { return nil }
            return (group.name,now-old)
        }.sorted { $0.1 > $1.1 }.prefix(3)
        if !growth.isEmpty {
            print("\nNE DEĞİŞTİ?  (aynı süreç üyeleri, ilk ve son örnek)")
            for (name,bytes) in growth { print("  \(cleanText(name)): +\(formatBytes(bytes)) bellek; sızıntı teşhisi değildir.") }
        }
    }
    if !markers.isEmpty {
        print("\nİŞARETLER")
        for marker in markers { print("  \(date.string(from: marker.timestamp)) · \(cleanText(marker.label))") }
    }
    let limits = Array(Set(s.limitations + warnings)).sorted()
    if !limits.isEmpty { print("\nKAPSAM"); for limit in limits { print("  \(cleanText(limit))") } }
}

private func run() throws {
    let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
    if options.help { print(help); return }
    if options.command == "version" { print("tawl \(BuildInfo.version)"); return }
    if options.command == "update" || options.command == "update-check" {
        let updates = UpdateService()
        let result = try updates.check()
        print(cleanText(result.message))
        guard options.command == "update", result.isUpdateAvailable else { return }
        if !options.assumeYes {
            guard isatty(STDIN_FILENO) != 0 else { throw CLIError("Onay için etkileşimli terminal gerekli; doğrudan güncelleme: tawl update --yes") }
            stderrLine("TAWL \(BuildInfo.version) → \(result.latestVersion) güncellensin mi? [y/N]")
            guard let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), ["y", "yes", "e", "evet"].contains(response) else {
                print("Güncelleme iptal edildi."); return
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
        if clockAdjusted { warnings.append("Sistem saati değişmiş: süre penceresi monotonik saatle hesaplandı; takvim saatleri geriye veya ileriye sıçrayabilir.") }
        var markers = recording.markers
        if options.lastSeconds != nil, let first = samples.first {
            if clockAdjusted {
                warnings.append("Sistem saati değişmiş: işaretleri süre penceresine kesin bağlamak mümkün değil; dosyanın tüm işaretleri gösteriliyor.")
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
        throw CLIError("Canlı ekran etkileşimli terminal gerektirir. ./tawl status veya record kullanın.")
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
        stderrLine("Kayıt başladı; Ctrl-C ile bitirebilirsiniz. Kayıt adları hassas bilgi içerebilir.")
        while interrupted == 0 {
            try writer?.append(next()); count += 1
            if ProcessInfo.processInfo.systemUptime >= end { break }
            let deadline = min(end, ProcessInfo.processInfo.systemUptime + 2)
            while interrupted == 0 && ProcessInfo.processInfo.systemUptime < deadline { usleep(50_000) }
        }
        try writer?.close()
        stderrLine("Kayıt tamamlandı: \(count) örnek.")
    }
}
do { try run() }
catch {
    let message = (error as? CLIError)?.description ?? error.localizedDescription
    stderrLine("tawl: " + message); exit(1)
}
