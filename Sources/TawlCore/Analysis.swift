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
        add("memory-pressure", latest.pressure == .critical ? "critical" : "warning", L10n.text("Memory pressure observed"),
            L10n.text("macOS memory pressure: \(pressureLabel(latest.pressure)). The largest visible applications are candidates for investigation; this measurement alone does not prove causation or a memory leak."), related: top.map(\.id))
        if let rate = latest.swapOutBytesPerSecond, rate > 0 {
            add("active-swap", "warning", L10n.text("Memory is being written to disk"), L10n.text("Swap-out in this interval: \(formatRate(rate)). Observed alongside memory pressure; any latency impact needs separate verification."))
        }
    } else if latest.pressure == .unknown {
        add("pressure-unknown", "info", L10n.text("Memory pressure unavailable"), L10n.text("Memory health was not inferred from RAM or swap usage."))
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
        add("partial-coverage", "info", L10n.text("Partial process visibility"),
            L10n.text("Unreadable identity: \(latest.unreadableProcessCount); missing memory: \(missingMemory); missing CPU rate: \(missingCPU) processes. Application totals cover visible processes."))
    }
    if findings.isEmpty {
        add("no-evidence", "info", L10n.text("No clear pressure evidence"),
            L10n.text("The defined thresholds were not exceeded in these measurements. Brief spikes, GPU load, disk latency, or application waits are not ruled out."))
    }
    return findings
}

// Shared with the streaming offline analyzer so threshold explanations cannot drift.
func sustainedCPUFinding(first: Snapshot, latest: Snapshot) -> Finding {
    let top = groupProcesses(latest, by: .application).filter { $0.cpuCores != nil }.sorted {
        if $0.cpuCores != $1.cpuCores { return ($0.cpuCores ?? 0) > ($1.cpuCores ?? 0) }
        return $0.id < $1.id
    }.prefix(3)
    return Finding(code: "sustained-cpu", severity: "warning", title: L10n.text("Sustained high CPU load"),
                   detail: L10n.text("Total CPU ≥85% across \(Int(latest.monotonicTime-first.monotonicTime)) consecutive seconds. This is a screening threshold; top consumers are listed without evidence of causation."),
                   start: first.timestamp, end: latest.timestamp, relatedWorkloadIDs: top.map(\.id))
}
