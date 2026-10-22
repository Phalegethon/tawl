import Foundation

/// Activity in the latest measured interval, independent of accumulated swap usage.
public enum SwapActivity { case writing, reading, idle, unknown }

public struct SwapAssessment {
    public let activity: SwapActivity
    public let title: String
    public let summary: String
    public let action: String
    public let limitation: String
    /// Observed change, not a forecast or a count attributable to any process.
    public let stockDeltaBytes: Int64?
    public let observedSeconds: Double?
    public let shouldReviewMemory: Bool
}

/// Uses system-wide rates and pressure. Neither footprint, compressed memory, nor
/// generic process page-ins identifies a process as the cause of swapping.
/// Sources: Apple Activity Monitor actmntr1004; XNU mach/vm_statistics.h,
/// mach/task_info.h and sys/resource.h. See docs/research/2026-10-22-swap-evidence.md.
public func assessSwap(snapshot: Snapshot, history: [Snapshot] = []) -> SwapAssessment {
    func validRate(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
    let incoming = validRate(snapshot.swapInBytesPerSecond)
    let outgoing = validRate(snapshot.swapOutBytesPerSecond)
    let activity: SwapActivity
    if let outgoing, outgoing > 0 { activity = .writing }
    else if let incoming, incoming > 0 { activity = .reading }
    else if incoming != nil && outgoing != nil { activity = .idle }
    else { activity = .unknown }

    let pressure = snapshot.pressure == .warning || snapshot.pressure == .critical
    let review = pressure || activity == .writing
    let title: String
    let summary: String
    switch activity {
    case .writing:
        title = "SWAP'A YAZILIYOR"
        summary = "Son ölçüm aralığında bellekteki sayfalar swap'a taşındı. Bu, hangi uygulamanın baskıyı başlattığını göstermez."
    case .reading:
        title = "SWAP'TAN OKUNUYOR"
        summary = "Son ölçüm aralığında swap'taki sayfalara yeniden erişildi. Okuma, swap kullanımının aynı miktarda azalacağı anlamına gelmez."
    case .idle:
        title = "SWAP AKTARIMI YOK"
        summary = pressure
            ? "Bu aralıkta swap aktarımı yok; sistem yine de bellek baskısı bildiriyor."
            : "Bu aralıkta swap aktarımı yok. Birikmiş swap miktarı tek başına güncel darboğaz kanıtı değildir."
    case .unknown:
        title = "SWAP AKTARIMI BİLİNMİYOR"
        summary = "Giriş/çıkış hızı için ölçüm eksik. Eksik veri sıfır aktarım sayılmaz."
    }
    let action: String
    if review {
        action = "Büyük ayak izli uygulamadaki gereksiz işi/sekmesini kaydedip normal kapat; ardından bellek baskısı ve swap'a yazma hızını karşılaştır. Swap'ın sıfırlanması hedef değildir."
    } else if snapshot.pressure == .unknown || activity == .unknown || outgoing == nil {
        action = "Yeni ölçümleri bekle; bellek baskısı ve swap'a yazma hızı birlikte bilinmeden yalnız swap miktarına göre uygulama kapatma."
    } else {
        action = "Baskı normal ve swap'a yazma yoksa sırf swap miktarı yüksek diye işlem gerekmez. Yeni yükte baskı ve yazma hızını izle."
    }

    // Stop at missing data or a collection gap; never borrow future samples when
    // evaluating a pinned/historical frame. A two-minute window is enough to show
    // direction without presenting it as a prediction of when swap will be empty.
    var older = snapshot
    var seconds: Double?
    if snapshot.monotonicTime.isFinite, snapshot.swapUsedBytes != nil {
        for candidate in history.reversed() {
            guard candidate.monotonicTime.isFinite else { break }
            if candidate.monotonicTime >= snapshot.monotonicTime { continue }
            let elapsed = older.monotonicTime - candidate.monotonicTime
            let total = snapshot.monotonicTime - candidate.monotonicTime
            guard elapsed > 0, elapsed <= 15, total <= 120,
                  let interval = older.intervalSeconds, interval.isFinite, interval > 0, interval <= 15,
                  abs(interval - elapsed) <= max(0.1, elapsed * 0.01),
                  candidate.swapUsedBytes != nil else { break }
            older = candidate; seconds = total
        }
    }
    var delta: Int64?
    if seconds != nil, let current = snapshot.swapUsedBytes, let start = older.swapUsedBytes {
        let magnitude = current >= start ? current - start : start - current
        if let signed = Int64(exactly: magnitude) { delta = current >= start ? signed : -signed }
    }
    if delta == nil { seconds = nil }
    return SwapAssessment(activity: activity, title: title, summary: summary, action: action,
                          limitation: "Süreç başına swap ölçülmüyor. Ayak izi swap payı veya kazanılacak RAM değildir; hangi süreç neden oldu, kaç GiB boşalır ve ne zaman azalır kesin hesaplanamaz.",
                          stockDeltaBytes: delta, observedSeconds: seconds, shouldReviewMemory: review)
}
