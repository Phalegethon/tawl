import Foundation

/// Compact system-only evidence. Time is absolute monotonic seconds. Interval
/// metrics describe (time - intervalSeconds, time]; nil is not a measured zero.
public struct ClosureImpactPoint {
    public let time: Double
    public let intervalSeconds: Double?
    public let cpuPercent: Double?
    public let pressure: Pressure
    public let swapUsedBytes: UInt64?
    public let swapOutBytesPerSecond: Double?
}

public struct ClosureImpactMean {
    public let value: Double?
    public let coverageSeconds: Double
}

public struct ClosureImpactWindowSummary {
    public let cpu: ClosureImpactMean
    public let swapOut: ClosureImpactMean
    public let pressure: Pressure
    public let swapUsedBytes: UInt64?
    public let sampleCount: Int
}

public struct ClosureImpactSummary {
    public let before: ClosureImpactWindowSummary
    public let after: ClosureImpactWindowSummary
    /// Difference in percentage points, not relative percentage change.
    public var cpuDeltaPercentagePoints: Double? {
        guard let a = before.cpu.value, let b = after.cpu.value else { return nil }
        return b - a
    }
    public var swapOutDeltaBytesPerSecond: Double? {
        guard let a = before.swapOut.value, let b = after.swapOut.value else { return nil }
        return b - a
    }
    public var swapUsedDeltaBytes: Int64? {
        guard let a = before.swapUsedBytes, let b = after.swapUsedBytes else { return nil }
        if b >= a { return Int64(exactly: b - a) }
        let amount = a - b
        if amount == UInt64(Int64.max) + 1 { return Int64.min }
        guard let signed = Int64(exactly: amount) else { return nil }
        return -signed
    }
}

/// Bounded before/after observations following an accepted termination request.
/// This records temporal changes, not causation or proof that the process exited.
/// Baseline and completion are immutable; lifecycle outcome belongs to the caller.
public struct ClosureImpact {
    public static let beforeDuration: Double = 30
    public static let afterDuration: Double = 60
    public static let maximumInterval: Double = 5
    public static let maximumBeforePoints = 121
    public static let maximumAfterPoints = 241

    public let intent: ProcessClosureIntent
    public let startedAt: Double
    public let startedOn: Date
    public private(set) var before: [ClosureImpactPoint] = []
    public private(set) var after: [ClosureImpactPoint] = []
    public private(set) var elapsed: Double = 0
    public private(set) var isComplete = false
    private var latestClock: Double
    private let validAnchor: Bool

    public init(intent: ProcessClosureIntent, startedAt: Double, startedOn: Date, history: [Snapshot]) {
        self.intent = intent; self.startedAt = startedAt; self.startedOn = startedOn
        latestClock = startedAt
        validAnchor = startedAt.isFinite && startedAt >= 0 && startedOn.timeIntervalSince1970.isFinite
        guard validAnchor else { isComplete = true; return }
        let left = max(0, startedAt - Self.beforeDuration)
        for snapshot in history {
            let time = snapshot.monotonicTime
            guard time.isFinite, time >= left, time <= startedAt,
                  before.last.map({ time > $0.time }) ?? true else { continue }
            before.append(Self.point(snapshot, lowerBound: left, previousTime: before.last?.time, isAfter: false))
            if before.count > Self.maximumBeforePoints { before.removeFirst() }
        }
    }

    /// A late/out-of-order frame never replaces accepted evidence. Advancing the
    /// observation clock is independent of whether this frame can be accepted.
    public mutating func observe(_ snapshot: Snapshot, now: Double) {
        guard validAnchor, !isComplete, now.isFinite, now >= latestClock else { return }
        defer { advance(now: now) }
        let time = snapshot.monotonicTime
        guard time.isFinite, time >= startedAt, time <= startedAt + Self.afterDuration,
              time <= now, now - time <= Self.maximumInterval,
              after.last.map({ time > $0.time }) ?? true else { return }
        after.append(Self.point(snapshot, lowerBound: startedAt, previousTime: after.last?.time, isAfter: true))
        if after.count > Self.maximumAfterPoints { after.removeFirst() }
    }

    /// Completes at the fixed horizon even if collection stopped. After completion,
    /// evidence and its freshness reference stay frozen at that horizon.
    public mutating func advance(now: Double) {
        guard validAnchor, !isComplete, now.isFinite, now >= latestClock else { return }
        latestClock = now
        elapsed = min(Self.afterDuration, now - startedAt)
        isComplete = elapsed >= Self.afterDuration
    }

    public var summary: ClosureImpactSummary {
        ClosureImpactSummary(before: Self.summarize(before, end: startedAt),
                             after: Self.summarize(after, end: startedAt + elapsed))
    }

    private static func point(_ snapshot: Snapshot, lowerBound: Double,
                              previousTime: Double?, isAfter: Bool) -> ClosureImpactPoint {
        let time = snapshot.monotonicTime
        var duration: Double?
        if let interval = snapshot.intervalSeconds, interval.isFinite, interval > 0,
           interval <= maximumInterval {
            let start = time - interval
            // Never include a sample average spanning the action boundary in the
            // after window. Baseline left-edge clipping is allowed explicitly.
            let crossesAction = isAfter && start < lowerBound
            let overlapsPrevious = previousTime.map { start < $0 - 0.000001 } ?? false
            let clipped = time - max(start, lowerBound)
            if !crossesAction && !overlapsPrevious && clipped > 0 { duration = clipped }
        }
        let cpu = snapshot.cpuPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        let swapOut = snapshot.swapOutBytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return ClosureImpactPoint(time: time, intervalSeconds: duration,
                                  cpuPercent: duration == nil ? nil : cpu, pressure: snapshot.pressure,
                                  swapUsedBytes: snapshot.swapUsedBytes,
                                  swapOutBytesPerSecond: duration == nil ? nil : swapOut)
    }

    private static func weightedMean(_ points: [ClosureImpactPoint],
                                     metric: KeyPath<ClosureImpactPoint, Double?>) -> ClosureImpactMean {
        var weight: Double = 0, mean: Double = 0
        for point in points {
            guard let value = point[keyPath: metric], let duration = point.intervalSeconds else { continue }
            let nextWeight = weight + duration
            // Incremental weighting avoids overflowing value * duration for large
            // finite byte rates. Missing points contribute no weight.
            mean += (value - mean) * (duration / nextWeight)
            weight = nextWeight
        }
        return ClosureImpactMean(value: weight > 0 && mean.isFinite ? mean : nil, coverageSeconds: weight)
    }

    private static func summarize(_ points: [ClosureImpactPoint], end: Double) -> ClosureImpactWindowSummary {
        let latest = points.last
        let fresh = latest.map { end.isFinite && end >= $0.time && end - $0.time <= maximumInterval } ?? false
        return ClosureImpactWindowSummary(cpu: weightedMean(points, metric: \.cpuPercent),
                                          swapOut: weightedMean(points, metric: \.swapOutBytesPerSecond),
                                          pressure: fresh ? latest!.pressure : .unknown,
                                          swapUsedBytes: fresh ? latest!.swapUsedBytes : nil,
                                          sampleCount: points.count)
    }
}
