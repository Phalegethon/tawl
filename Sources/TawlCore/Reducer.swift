import Foundation

public final class SnapshotReducer {
    private var previous: RawReading?
    private let attributor = Attributor()
    public init() {}
    public func reduce(_ reading: RawReading) -> Snapshot {
        defer { previous = reading }
        var s = Snapshot(timestamp: reading.timestamp, monotonicTime: reading.monotonicTime)
        s.logicalCPUCount = reading.logicalCPUCount; s.memoryTotalBytes = reading.memoryTotalBytes
        s.pressure = reading.pressure; s.compressedBytes = reading.compressedBytes; s.swapUsedBytes = reading.swapUsedBytes
        s.totalProcessCount = reading.totalProcessCount; s.unreadableProcessCount = reading.unreadableProcessCount
        s.limitations = reading.limitations.map(cleanText)
        let elapsed = previous.map { reading.monotonicTime - $0.monotonicTime }
        // A long pause resets the baseline; never average a sleep interval into a healthy rate.
        let valid = elapsed.map { $0 > 0 && $0 <= 15 && $0.isFinite } ?? false
        if valid { s.intervalSeconds = elapsed }
        else { s.limitations.append(previous == nil ? L10n.text("First sample: waiting for a second measurement to calculate rates.") : L10n.text("Gap in the sampling interval; rates are restarting.")) }
        func rate(_ now: UInt64?, _ old: UInt64?) -> Double? {
            guard valid, let elapsed, let now, let old, now >= old else { return nil }
            return Double(now - old) / elapsed
        }
        if valid, let now = reading.cpuTicks, let old = previous?.cpuTicks,
           now.total > old.total, now.busy >= old.busy {
            s.cpuPercent = min(100, Double(now.busy-old.busy) / Double(now.total-old.total) * 100)
        }
        s.cpuCores = reduceCores(reading.cpuCores, previous: previous?.cpuCores, validInterval: valid)
        s.gpus = reading.gpus.map { devices in
            devices.map { gpu in
                var result = gpu
                result.name = cleanText(gpu.name)
                if !HardwareLimits.percentage(gpu.utilizationPercent) { result.utilizationPercent = nil }
                if !HardwareLimits.percentage(gpu.rendererUtilizationPercent) { result.rendererUtilizationPercent = nil }
                if !HardwareLimits.percentage(gpu.tilerUtilizationPercent) { result.tilerUtilizationPercent = nil }
                return result
            }
        }
        s.swapInBytesPerSecond = rate(reading.swapInBytes, previous?.swapInBytes)
        s.swapOutBytesPerSecond = rate(reading.swapOutBytes, previous?.swapOutBytes)
        s.networkInBytesPerSecond = rate(reading.networkInBytes, previous?.networkInBytes)
        s.networkOutBytesPerSecond = rate(reading.networkOutBytes, previous?.networkOutBytes)
        s.diskReadBytesPerSecond = rate(reading.diskReadBytes, previous?.diskReadBytes)
        s.diskWriteBytesPerSecond = rate(reading.diskWriteBytes, previous?.diskWriteBytes)
        let oldProcesses = Dictionary((previous?.processes ?? []).map { ($0.id,$0) }, uniquingKeysWith: { a,_ in a })
        s.processes = reading.processes.map { p in
            let identity = attributor.identify(p, among: reading.processes)
            let old = oldProcesses[p.id]
            let cpu = rate(p.cpuNanoseconds, old?.cpuNanoseconds).map { $0 / 1_000_000_000 }
            var delta: Int64?
            if valid, let now = p.footprintBytes, let before = old?.footprintBytes,
               now <= UInt64(Int64.max), before <= UInt64(Int64.max) { delta = Int64(now) - Int64(before) }
            let age = reading.timestamp.timeIntervalSince1970 - Double(p.startedAt) / 1_000_000
            let validAge: Double? = p.startedAt > 0 && age.isFinite && age >= 0 ? age : nil
            let path = p.executablePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            let thirdPartyApp = path.map { ($0.hasPrefix("/Applications/") || $0.hasPrefix("/Users/")) && $0.contains(".app/") } ?? false
            return ProcessSample(id: p.id, pid: p.pid, name: cleanText(p.name),
                                 applicationID: identity.applicationID, applicationName: identity.applicationName,
                                 projectID: identity.projectID, projectName: identity.projectName, projectEvidence: identity.projectEvidence,
                                 cpuCores: cpu, footprintBytes: p.footprintBytes, memoryDeltaBytes: delta,
                                 diskReadBytesPerSecond: rate(p.diskReadBytes, old?.diskReadBytes),
                                 diskWriteBytesPerSecond: rate(p.diskWriteBytes, old?.diskWriteBytes),
                                 ageSeconds: validAge, canReviewClosure: p.isOwnedByCurrentUser == true && thirdPartyApp)
        }
        return s
    }
}

private func reduceCores(_ current: [RawCPUCore]?, previous: [RawCPUCore]?, validInterval: Bool) -> [CPUCoreSample]? {
    guard let current, current.count <= HardwareLimits.cpuCount,
          current.allSatisfy({ (0...HardwareLimits.cpuID).contains($0.id) }),
          Set(current.map(\.id)).count == current.count else { return nil }
    let previous = previous ?? []
    let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let sameTopology = old.count == current.count && previous.count == current.count &&
        current.allSatisfy { old[$0.id]?.kind == $0.kind }
    return current.sorted { $0.id < $1.id }.map { core in
        var utilization: Double?
        if validInterval && sameTopology, let before = old[core.id],
           core.user >= before.user, core.system >= before.system, core.nice >= before.nice, core.idle >= before.idle {
            // Decreasing uint32 counters (including wrap) reset one interval rather than
            // guessing whether the counter wrapped or the processor was reinitialized.
            let busy = UInt64(core.user - before.user) + UInt64(core.system - before.system) + UInt64(core.nice - before.nice)
            let total = busy + UInt64(core.idle - before.idle)
            if total > 0 { utilization = Double(busy) / Double(total) * 100 }
        }
        return CPUCoreSample(id: core.id, kind: core.kind, utilizationPercent: utilization)
    }
}
