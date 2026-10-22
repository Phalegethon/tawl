import Foundation

public enum ResourceSeverity: Int, Comparable {
    case warning = 1, critical = 2
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public enum ResourceKind: String { case cpu, memory, growth }
public struct ResourceSignal {
    public let resource: ResourceKind
    public let severity: ResourceSeverity
    public var label: String {
        switch resource { case .cpu: return "CPU"; case .memory: return "BELLEK"; case .growth: return "ARTIŞ" }
    }
}
public enum RecommendationKind { case sustainedCPU, memoryPressure, quietMemory }
public struct ProcessRecommendation {
    public let kind: RecommendationKind
    public let title: String
    public let evidence: String
    public let action: String
    public let caveat: String
}
public enum QuietObservationState {
    case exited, `protected`, unknownAge, young, missingMetrics, active, observing, qualified
}
public struct ProcessAssessment {
    public var signals: [ResourceSignal] = []
    public var recommendations: [ProcessRecommendation] = []
    public var idleStatus: String = ""
    /// Nil means not evaluated; zero means measured but no continuous evidence yet.
    public var quietSeconds: Double?
    public var highCPUSeconds: Double?
    public var quietObservationState: QuietObservationState = .exited
}

fileprivate struct ProcessEvidenceMetrics: Equatable {
    let cpu: Double?
    let memory: UInt64?
    let read: Double?
    let write: Double?
    init(_ process: ProcessSample) {
        cpu = process.cpuCores; memory = process.footprintBytes
        read = process.diskReadBytesPerSecond; write = process.diskWriteBytesPerSecond
    }
    var highCPU: Bool { cpu.map { $0.isFinite && $0 >= 1 } ?? false }
    var quiet: Bool {
        guard let cpu, cpu.isFinite, cpu >= 0, cpu < 0.02,
              let memory, memory >= 268_435_456,
              let read, read.isFinite, read >= 0, read < 1024,
              let write, write.isFinite, write >= 0, write < 1024 else { return false }
        return true
    }
}

/// Small continuity proof for one current process. Detailed history may be evicted
/// without losing these bounded durations; this is not a historical measurement store.
public struct ProcessEvidence {
    public let processID: String
    public let monotonicTime: Double
    public let highCPUSeconds: Double
    public let quietSeconds: Double
    fileprivate let metrics: ProcessEvidenceMetrics

    fileprivate func matches(_ process: ProcessSample, snapshot: Snapshot) -> Bool {
        processID == process.id && monotonicTime == snapshot.monotonicTime &&
        metrics == ProcessEvidenceMetrics(process)
    }
}

/// Retains only current process identities, the latest four measurements, and two
/// capped counters. No sample arrays or exited identities survive an update.
public struct ProcessEvidenceTracker {
    private var latestTime: Double?
    private var current: [String: ProcessEvidence] = [:]
    public init() {}
    public var trackedProcessCount: Int { current.count }

    public mutating func update(_ snapshot: Snapshot) {
        guard snapshot.monotonicTime.isFinite else {
            current.removeAll(keepingCapacity: false); latestTime = nil; return
        }
        let elapsed = latestTime.map { snapshot.monotonicTime - $0 }
        let continuous: Bool
        if let elapsed, elapsed.isFinite, elapsed > 0, elapsed <= 15,
           let interval = snapshot.intervalSeconds, interval.isFinite, interval > 0, interval <= 15,
           abs(interval - elapsed) <= max(0.1, elapsed * 0.01) {
            continuous = true
        } else { continuous = false }
        var next: [String: ProcessEvidence] = [:]
        next.reserveCapacity(snapshot.processes.count)
        for process in snapshot.processes where next[process.id] == nil {
            let metrics = ProcessEvidenceMetrics(process)
            let prior = current[process.id]
            let high: Double
            let quietTime: Double
            if continuous, let elapsed, let prior {
                high = metrics.highCPU && prior.metrics.highCPU ? min(30, prior.highCPUSeconds + elapsed) : 0
                quietTime = metrics.quiet && prior.metrics.quiet ? min(600, prior.quietSeconds + elapsed) : 0
            } else { high = 0; quietTime = 0 }
            next[process.id] = ProcessEvidence(processID: process.id, monotonicTime: snapshot.monotonicTime,
                                              highCPUSeconds: high, quietSeconds: quietTime, metrics: metrics)
        }
        current = next; latestTime = snapshot.monotonicTime
    }

    public func evidence(for process: ProcessSample, at snapshot: Snapshot) -> ProcessEvidence? {
        guard latestTime == snapshot.monotonicTime,
              let measured = snapshot.processes.first(where: { $0.id == process.id }),
              let proof = current[process.id], proof.matches(measured, snapshot: snapshot) else { return nil }
        return proof
    }
}

/// Attention thresholds, not diagnoses or percentages of physical RAM.
public func resourceSignals(cpuCores: Double?, footprintBytes: UInt64?, memoryDeltaBytes: Int64?) -> [ResourceSignal] {
    var signals: [ResourceSignal] = []
    if let cpuCores, cpuCores.isFinite, cpuCores >= 1 {
        signals.append(ResourceSignal(resource: .cpu, severity: cpuCores >= 2 ? .critical : .warning))
    }
    if let footprintBytes, footprintBytes >= 2_147_483_648 {
        signals.append(ResourceSignal(resource: .memory, severity: footprintBytes >= 4_294_967_296 ? .critical : .warning))
    }
    if let memoryDeltaBytes, memoryDeltaBytes >= 104_857_600 {
        signals.append(ResourceSignal(resource: .growth, severity: .warning))
    }
    return signals
}

/// Backward from this exact snapshot only. A missing member, changed lifetime, counter gap,
/// or invalid interval breaks the evidence; time before the first valid sample is not counted.
private func observedDuration(processID: String, snapshot: Snapshot, history: [Snapshot],
                              limit: Double, accepts: (ProcessSample) -> Bool) -> Double {
    guard let current = snapshot.processes.first(where: { $0.id == processID }), accepts(current),
          snapshot.monotonicTime.isFinite else { return 0 }
    var newer = snapshot
    var duration = 0.0
    for older in history.reversed() {
        if older.monotonicTime > snapshot.monotonicTime { continue }
        if older.monotonicTime == snapshot.monotonicTime { continue }
        let elapsed = newer.monotonicTime - older.monotonicTime
        guard elapsed.isFinite, elapsed > 0, elapsed <= 15,
              let interval = newer.intervalSeconds, interval.isFinite, interval > 0, interval <= 15,
              abs(interval - elapsed) <= max(0.1, elapsed * 0.01),
              let prior = older.processes.first(where: { $0.id == processID }), accepts(prior) else { break }
        duration += elapsed
        if duration >= limit { break }
        newer = older
    }
    return duration
}

private func quiet(_ process: ProcessSample) -> Bool {
    ProcessEvidenceMetrics(process).quiet
}

public func assessProcess(_ process: ProcessSample, snapshot: Snapshot, history: [Snapshot],
                          evidence: ProcessEvidence? = nil) -> ProcessAssessment {
    guard let current = snapshot.processes.first(where: { $0.id == process.id }) else {
        return ProcessAssessment(idleStatus: "Süreç bu örnekte yok; kapatma önerisi üretilemiyor.")
    }
    var result = ProcessAssessment(signals: resourceSignals(cpuCores: current.cpuCores,
                                                           footprintBytes: current.footprintBytes,
                                                           memoryDeltaBytes: current.memoryDeltaBytes))
    // App-family grouping intentionally hides worker categories; safety review must
    // still recognize a database/VM daemon embedded in a development application.
    var executableIdentity = current
    executableIdentity.applicationName = current.name
    executableIdentity.applicationID = "process:" + current.id
    let categories = [usageCategory(for: current), usageCategory(for: executableIdentity)]
    if let category = categories.first(where: { $0 == .virtualization || $0 == .databases || $0 == .system }) {
        result.quietObservationState = .protected
        result.idleStatus = "\(category.title) servisi: düşük CPU, gereksiz olduğu anlamına gelmez. Bağımlı işleri servis/VM yönetiminden incele; kapatma önerisi üretilmiyor."
        return result
    }
    guard current.canReviewClosure == true else {
        result.quietObservationState = .protected
        result.idleStatus = "Sahiplik/uygulama doğrulanamadı veya sistem süreci: kapatma önerisi yok."
        return result
    }
    let app = cleanText(current.applicationName)
    let action = "Önce \(app) içindeki işi/sekmesini kontrol et; gerekmiyorsa kaydedip uygulamadan normal çık. Canlı ekranda x ile uygulama etkisini inceleyip bu süreç için sonlandırma isteğini onaylayabilirsin."
    let proof = evidence.flatMap { $0.matches(current, snapshot: snapshot) ? $0 : nil }
    let highCPU = proof?.highCPUSeconds ?? observedDuration(processID: current.id, snapshot: snapshot, history: history, limit: 30) { p in
        ProcessEvidenceMetrics(p).highCPU
    }
    if let cpu = current.cpuCores, cpu.isFinite, cpu >= 0 {
        result.highCPUSeconds = min(30, highCPU)
    }
    if highCPU >= 30 {
        result.recommendations.append(ProcessRecommendation(
            kind: .sustainedCPU, title: "Sürekli CPU tüketimini incele",
            evidence: "En az \(Int(highCPU)) sn boyunca ≥1 çekirdek; şu an \(String(format: "%.2f", current.cpuCores ?? 0)) çekirdek.",
            action: action, caveat: "Derleme, video veya beklenen bir iş olabilir; bu ölçüm tek başına takılma kanıtı değildir."))
    }
    if (snapshot.pressure == .warning || snapshot.pressure == .critical),
       let memory = current.footprintBytes, memory >= 2_147_483_648 {
        result.recommendations.append(ProcessRecommendation(
            kind: .memoryPressure, title: "Bellek baskısına katkısını incele",
            evidence: "Sistem bellek baskısı var; bu süreç \(formatBytes(memory)) ayak izi taşıyor.",
            action: action, caveat: "Büyük ayak izi baskının kesin nedeni değildir; uygulama kapanınca kazanılacak RAM bu değerle aynı olmayabilir."))
    }
    guard let age = current.ageSeconds, age.isFinite, age >= 0 else {
        result.quietObservationState = .unknownAge
        result.idleStatus = "Süreç yaşı bilinmiyor; uzun süredir açık değerlendirmesi yapılamıyor."
        return result
    }
    if age < 7200 {
        result.quietObservationState = .young
        result.idleStatus = "Uzun süre açık adayı değil: süreç yaşı 2 saatten az."
        return result
    }
    let quietTime = proof?.quietSeconds ?? observedDuration(processID: current.id, snapshot: snapshot, history: history, limit: 600, accepts: quiet)
    if quietTime >= 600 {
        result.quietSeconds = 600
        result.quietObservationState = .qualified
        result.recommendations.append(ProcessRecommendation(
            kind: .quietMemory, title: "Uzun süredir açık, düşük etkinlik adayı",
            evidence: "Yaş ≥2 saat; son 10 dk CPU <0.02 çekirdek, disk okuma/yazma <1 KiB/sn, ayak izi ≥256 MiB.",
            action: "\(app) içindeki bu işin hâlâ gerekli olup olmadığını kontrol et. Gerekmiyorsa kaydedip normal kapat.",
            caveat: "Bu, kullanılmıyor demek değildir: pencere/klavye etkileşimi ve süreç bazında ağ etkinliği ölçülmüyor; arka plan işi olabilir."))
        result.idleStatus = "10 dk düşük CPU/disk etkinliği gözlendi; kullanım durumu bilinmiyor."
    } else if current.cpuCores.map({ !$0.isFinite || $0 < 0 }) ?? true ||
              current.diskReadBytesPerSecond.map({ !$0.isFinite || $0 < 0 }) ?? true ||
              current.diskWriteBytesPerSecond.map({ !$0.isFinite || $0 < 0 }) ?? true || current.footprintBytes == nil {
        result.quietObservationState = .missingMetrics
        result.idleStatus = "Düşük etkinlik için CPU/bellek/disk kanıtı eksik; boşta kabul edilmiyor."
    } else if !quiet(current) {
        result.quietSeconds = 0
        result.quietObservationState = .active
        result.idleStatus = "Düşük etkinlik koşulları şu an sağlanmıyor (CPU, disk veya ayak izi)."
    } else {
        result.quietSeconds = min(600, quietTime)
        result.quietObservationState = .observing
        result.idleStatus = "Düşük etkinlik gözlemi \(Int(quietTime))/600 sn; kesintisiz 10 dk kanıt gerekiyor."
    }
    return result
}
