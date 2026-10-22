import Foundation

/// Select a trailing elapsed-time window without being affected by wall-clock corrections.
public func reportWindow(_ snapshots: [Snapshot], lastSeconds: Double?) -> [Snapshot] {
    guard let seconds = lastSeconds else { return snapshots }
    guard seconds.isFinite, seconds >= 0, let latest = snapshots.last,
          latest.monotonicTime.isFinite else { return [] }
    let cutoff = latest.monotonicTime - seconds
    return snapshots.filter { $0.monotonicTime >= cutoff && $0.monotonicTime <= latest.monotonicTime }
}

/// Summarize observed episodes across a selected recording window. Live analysis remains unchanged.
public func analyzeSession(_ snapshots: [Snapshot]) -> [Finding] {
    guard !snapshots.isEmpty else { return [] }
    var episodes: [Finding] = []
    var activeEpisodes: [String: Int] = [:]
    var highRunStart: Int?
    var horizonStart = 0
    var latestInformation: [Finding] = []

    for index in snapshots.indices {
        let sample = snapshots[index]
        if index > 0 {
            let gap = sample.monotonicTime - snapshots[index - 1].monotonicTime
            if !gap.isFinite || gap <= 0 || gap > 5 {
                highRunStart = nil
                horizonStart = index
                activeEpisodes.removeAll()
            }
        }
        // Instantaneous pressure and coverage need only this sample. Never copy or rescan a
        // growing history: dense but valid recordings can have many samples in a short interval.
        var findings = analyze([sample])
        if let cpu = sample.cpuPercent, cpu >= 85 {
            if highRunStart == nil || sample.intervalSeconds == nil {
                highRunStart = index
                horizonStart = index
            }
            // Each index advances at most once. Keep the sample reaching/crossing 60 s,
            // matching the live rule without rescanning its high-CPU suffix.
            while horizonStart < index && snapshots[horizonStart + 1].monotonicTime <= sample.monotonicTime - 60 {
                horizonStart += 1
            }
            if sample.monotonicTime - snapshots[horizonStart].monotonicTime >= 30 {
                findings.append(sustainedCPUFinding(first: snapshots[horizonStart], latest: sample))
            }
        } else {
            highRunStart = nil
            horizonStart = index
        }
        if index == snapshots.endIndex - 1 {
            latestInformation = findings.filter { $0.severity == "info" }
        }
        var nextActive: [String: Int] = [:]
        for finding in findings where finding.severity == "warning" || finding.severity == "critical" {
            let key = finding.code + ":" + finding.severity
            if let episodeIndex = activeEpisodes[key] {
                // Preserve the first evidence window and extend only across consecutive evidence.
                episodes[episodeIndex].end = finding.end
                episodes[episodeIndex].detail = episodeDetail(finding)
                episodes[episodeIndex].relatedWorkloadIDs = recentCandidates(
                    episodes[episodeIndex].relatedWorkloadIDs, adding: finding.relatedWorkloadIDs)
                nextActive[key] = episodeIndex
            } else {
                var episode = finding
                episode.title = episodeTitle(finding)
                episode.detail = episodeDetail(finding)
                episode.relatedWorkloadIDs = recentCandidates([], adding: finding.relatedWorkloadIDs)
                nextActive[key] = episodes.count
                episodes.append(episode)
            }
        }
        activeEpisodes = nextActive
    }
    // Coverage statements explicitly describe the latest sample. Earlier observed episodes must
    // never be contradicted by a generic "no evidence" line after the system has recovered.
    let information = latestInformation.compactMap { finding -> Finding? in
        if finding.code == "no-evidence" && !episodes.isEmpty { return nil }
        var latest = finding
        latest.title = "Son örnek: " + finding.title
        return latest
    }
    return episodes + information
}

private func recentCandidates(_ previous: [String], adding current: [String]) -> [String] {
    var result = previous
    for identifier in current {
        result.removeAll { $0 == identifier }
        result.append(identifier)
    }
    return Array(result.suffix(12))
}

private func episodeTitle(_ finding: Finding) -> String {
    switch finding.code {
    case "memory-pressure": return "Seçili aralıkta bellek baskısı gözlendi"
    case "active-swap": return "Seçili aralıkta diske bellek aktarımı gözlendi"
    case "sustained-cpu": return "Seçili aralıkta sürekli yüksek CPU yükü gözlendi"
    default: return finding.title
    }
}

private func episodeDetail(_ finding: Finding) -> String {
    "Son kanıt penceresi: " + finding.detail
}
