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
        title = L10n.text("WRITING TO SWAP")
        summary = L10n.text("Memory pages moved to swap during the latest interval. This does not identify the application that initiated pressure.")
    case .reading:
        title = L10n.text("READING FROM SWAP")
        summary = L10n.text("Pages in swap were accessed again during the latest interval. Reading does not mean swap usage will decrease by the same amount.")
    case .idle:
        title = L10n.text("NO SWAP TRANSFER")
        summary = pressure
            ? L10n.text("No swap transfer in this interval; the system still reports memory pressure.")
            : L10n.text("No swap transfer in this interval. Accumulated swap alone does not prove a current bottleneck.")
    case .unknown:
        title = L10n.text("SWAP TRANSFER UNKNOWN")
        summary = L10n.text("Read/write rate measurements are missing. Missing data does not mean zero transfer.")
    }
    let action: String
    if review {
        action = L10n.text("Save and normally close unnecessary tasks/tabs in applications with large footprints; then compare memory pressure and swap write rate. Zero swap is not the goal.")
    } else if snapshot.pressure == .unknown || activity == .unknown || outgoing == nil {
        action = L10n.text("Wait for new measurements; do not close applications based only on swap usage before both memory pressure and swap write rate are known.")
    } else {
        action = L10n.text("If pressure is normal and there are no swap writes, high swap usage alone requires no action. Monitor pressure and write rate under new load.")
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
                          limitation: L10n.text("Per-process swap is not measured. Footprint is neither swap share nor recoverable RAM; the responsible process, recoverable GiB, and time to decrease cannot be calculated precisely."),
                          stockDeltaBytes: delta, observedSeconds: seconds, shouldReviewMemory: review)
}
