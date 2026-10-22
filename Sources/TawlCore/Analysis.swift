import Foundation

public func analyze(_ snapshots: [Snapshot]) -> [Finding] {
    guard let latest = snapshots.last else { return [] }
    var findings: [Finding] = []
    func add(_ code: String, _ severity: String, _ title: String, _ detail: String, start: Date? = nil, related: [String] = []) {
        findings.append(Finding(code: code, severity: severity, title: title, detail: detail,
                                start: start ?? latest.timestamp, end: latest.timestamp, relatedWorkloadIDs: related))
    }
    if latest.pressure == .warning || latest.pressure == .critical {
        let top = groupProcesses(latest, by: .application).filter { $0.footprintBytes != nil }.prefix(3)
        add("memory-pressure", latest.pressure == .critical ? "critical" : "warning", "Bellek baskısı gözleniyor",
            "macOS bellek baskısı: \(pressureLabel(latest.pressure)). En büyük görünen uygulamalar inceleme adayıdır; bu ölçüm tek başına neden veya bellek sızıntısı kanıtı değildir.", related: top.map(\.id))
        if let rate = latest.swapOutBytesPerSecond, rate > 0 {
            add("active-swap", "warning", "Diske bellek aktarımı var", "Bu aralıkta swap-out \(formatRate(rate)). Bellek baskısıyla aynı anda gözlendi; gecikme etkisi ayrıca doğrulanmalı.")
        }
    } else if latest.pressure == .unknown {
        add("pressure-unknown", "info", "Bellek baskısı ölçülemedi", "RAM veya swap miktarından bellek sağlığı sonucu çıkarılmadı.")
    }
    if let cpu = latest.cpuPercent, cpu >= 85 {
        var first = latest
        for sample in snapshots.dropLast().reversed() {
            let gap = first.monotonicTime - sample.monotonicTime
            guard gap > 0, gap <= 5, first.intervalSeconds != nil,
                  let cpu = sample.cpuPercent, cpu >= 85 else { break }
            first = sample
            if latest.monotonicTime - sample.monotonicTime >= 60 { break }
        }
        if latest.monotonicTime-first.monotonicTime >= 30 {
            findings.append(sustainedCPUFinding(first: first, latest: latest))
        }
    }
    let missingCPU = latest.processes.filter { $0.cpuCores == nil }.count
    let missingMemory = latest.processes.filter { $0.footprintBytes == nil }.count
    if latest.unreadableProcessCount > 0 || missingMemory > 0 {
        add("partial-coverage", "info", "Süreç görünürlüğü kısmi",
            "Kimliği okunamayan \(latest.unreadableProcessCount), belleği eksik \(missingMemory), CPU hızı eksik \(missingCPU) süreç. Uygulama toplamları görünen kapsamı içerir.")
    }
    if findings.isEmpty {
        add("no-evidence", "info", "Belirgin baskı kanıtı yok",
            "Bu ölçümlerde tanımlı eşikler aşılmadı. Kısa sıçramalar, GPU, disk gecikmesi veya uygulama içi beklemeler bu sonuçla dışlanmaz.")
    }
    return findings
}

// Shared with the streaming offline analyzer so threshold explanations cannot drift.
func sustainedCPUFinding(first: Snapshot, latest: Snapshot) -> Finding {
    let top = groupProcesses(latest, by: .application).filter { $0.cpuCores != nil }.sorted {
        if $0.cpuCores != $1.cpuCores { return ($0.cpuCores ?? 0) > ($1.cpuCores ?? 0) }
        return $0.id < $1.id
    }.prefix(3)
    return Finding(code: "sustained-cpu", severity: "warning", title: "CPU yükü uzun süredir yüksek",
                   detail: "Kesintisiz \(Int(latest.monotonicTime-first.monotonicTime)) saniyelik örneklerde toplam CPU ≥ %85. Bu bir tarama eşiğidir; en yüksek tüketen uygulamalar neden kanıtı olmadan listelenir.",
                   start: first.timestamp, end: latest.timestamp, relatedWorkloadIDs: top.map(\.id))
}
