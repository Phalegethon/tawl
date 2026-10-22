import Foundation
import CTawl
import Darwin

public final class NativeCollector {
    private var networkSignature: UInt64?
    private var diskSignature: UInt64?
    public init() {}

    public func collect() -> RawReading {
        var reading = RawReading()
        guard let pointer = nb_collect() else {
            reading.limitations = [L10n.text("Could not allocate a system sample; counters unavailable.")]
            return reading
        }
        defer { nb_free_reading(pointer) }
        let native = pointer.pointee
        func valid(_ flag: Int) -> Bool { native.valid & UInt32(flag) != 0 }
        reading.monotonicTime = native.monotonic_seconds
        reading.logicalCPUCount = Int(native.logical_cpus)
        if valid(NB_CPU_VALID) { reading.cpuTicks = CPUTicks(busy: native.cpu_busy, total: native.cpu_total) }
        else { reading.limitations.append(L10n.text("System CPU counters unavailable.")) }
        collectHardware(into: &reading)
        if valid(NB_MEMORY_VALID) { reading.memoryTotalBytes = native.memory_total }
        else { reading.limitations.append(L10n.text("Total physical memory unavailable.")) }
        if valid(NB_VM_VALID) {
            reading.compressedBytes = native.compressed_bytes
            reading.swapInBytes = native.swap_in_bytes
            reading.swapOutBytes = native.swap_out_bytes
        } else { reading.limitations.append(L10n.text("Compressed-memory and swap-activity counters unavailable.")) }
        if valid(NB_SWAP_VALID) { reading.swapUsedBytes = native.swap_used_bytes }
        else { reading.limitations.append(L10n.text("Swap usage unavailable.")) }
        if valid(NB_PRESSURE_VALID) {
            reading.pressure = native.pressure_level == 1 ? .normal : native.pressure_level == 2 ? .warning : .critical
        } else { reading.limitations.append(L10n.text("Operating-system memory-pressure signal unavailable.")) }

        if valid(NB_NETWORK_VALID) {
            if networkSignature == nil || networkSignature == native.network_signature {
                reading.networkInBytes = native.network_in_bytes
                reading.networkOutBytes = native.network_out_bytes
            } else { reading.limitations.append(L10n.text("Network interfaces changed; network rates were not calculated for this interval.")) }
            networkSignature = native.network_signature
        } else { networkSignature = nil; reading.limitations.append(L10n.text("Physical network-interface counters unavailable.")) }
        reading.limitations.append(L10n.text("Network: total across en* Ethernet/Wi-Fi interfaces; excludes loopback, tunnels, virtual bridges, and differently named interfaces."))
        if valid(NB_DISK_VALID) {
            if diskSignature == nil || diskSignature == native.disk_signature {
                reading.diskReadBytes = native.disk_read_bytes
                reading.diskWriteBytes = native.disk_write_bytes
            } else { reading.limitations.append(L10n.text("Disk devices changed; disk rates were not calculated for this interval.")) }
            diskSignature = native.disk_signature
            reading.limitations.append(L10n.text("Disk: \(native.disk_driver_count) physical block-device drivers reporting IOKit counters; excludes \(native.disk_virtual_count) virtual devices. This is not file I/O latency."))
        } else { diskSignature = nil; reading.limitations.append(L10n.text("System disk I/O counters unavailable.")) }
        if native.disk_unknown_count > 0 { reading.limitations.append(L10n.text("Could not determine whether \(native.disk_unknown_count) disk drivers are physical or virtual; no partial total was shown.")) }

        reading.totalProcessCount = Int(native.listed_process_count)
        reading.unreadableProcessCount = Int(native.unreadable_process_count)
        var missingUsage = 0, deniedUsage = 0, missingPath = 0, missingCWD = 0, deniedCWD = 0
        if let processes = native.processes {
            reading.processes.reserveCapacity(Int(native.process_count))
            for index in 0..<Int(native.process_count) {
                let process = processes[index]
                let usageAvailable = process.valid & UInt32(NB_PROCESS_USAGE_VALID) != 0
                let pathAvailable = process.valid & UInt32(NB_PROCESS_PATH_VALID) != 0
                let cwdAvailable = process.valid & UInt32(NB_PROCESS_CWD_VALID) != 0
                var raw = RawProcess(pid: process.pid, parentPID: process.parent_pid,
                                     startedAt: process.start_microseconds, name: nativeString(process.name),
                                     executablePath: pathAvailable ? nativeString(process.executable_path) : nil,
                                     workingDirectory: cwdAvailable ? nativeString(process.working_directory) : nil,
                                     cpuNanoseconds: usageAvailable ? process.cpu_nanoseconds : nil,
                                     footprintBytes: usageAvailable ? process.footprint_bytes : nil)
                raw.residentBytes = usageAvailable ? process.resident_bytes : nil
                raw.isOwnedByCurrentUser = process.is_owned_by_current_user != 0
                raw.diskReadBytes = usageAvailable ? process.disk_read_bytes : nil
                raw.diskWriteBytes = usageAvailable ? process.disk_write_bytes : nil
                reading.processes.append(raw)
                if !usageAvailable { missingUsage += 1; if isDenied(process.usage_error) { deniedUsage += 1 } }
                if !pathAvailable { missingPath += 1 }
                if !cwdAvailable { missingCWD += 1; if isDenied(process.cwd_error) { deniedCWD += 1 } }
            }
        }
        if !valid(NB_PROCESS_LIST_VALID) { reading.limitations.append(L10n.text("Process list unavailable; process coverage unknown.")) }
        if valid(NB_PROCESS_LIST_TRUNCATED) { reading.limitations.append(L10n.text("The process list grew during sampling; coverage may be partial.")) }
        if native.unreadable_process_count > 0 {
            reading.limitations.append(L10n.text("Unreadable identity for \(native.unreadable_process_count) processes: \(native.identity_denied_count) permission denials, \(native.identity_changed_count) exits/identity changes, \(native.identity_other_error_count) other errors."))
        }
        if missingUsage > 0 { reading.limitations.append(L10n.text("Missing CPU/memory/disk counters for \(missingUsage) processes (\(deniedUsage) permission denials); unknown fields are not zero.")) }
        if missingPath > 0 { reading.limitations.append(L10n.text("Executable paths unavailable for \(missingPath) processes.")) }
        if missingCWD > 0 { reading.limitations.append(L10n.text("Working directories unavailable for \(missingCWD) processes (\(deniedCWD) permission denials); project attribution is partial.")) }
        reading.limitations.append(L10n.text("Process coverage includes PID > 0; work that starts and ends between samples may be missed."))
        return reading
    }
}

private func collectHardware(into reading: inout RawReading) {
    guard let pointer = nb_collect_hardware() else {
        reading.limitations.append(L10n.text("CPU-core and GPU measurements unavailable.")); return
    }
    defer { nb_free_hardware(pointer) }
    let hardware = pointer.pointee
    if hardware.valid & UInt32(NB_HARDWARE_CPU_VALID) != 0, let cores = hardware.cpus {
        reading.cpuCores = (0..<Int(hardware.cpu_count)).map { index in
            let core = cores[index]
            let kind: CPUCoreKind = core.kind == NB_CPU_KIND_EFFICIENCY ? .efficiency : core.kind == NB_CPU_KIND_PERFORMANCE ? .performance : .unknown
            return RawCPUCore(id: Int(core.id), kind: kind, user: core.user, system: core.system, nice: core.nice, idle: core.idle)
        }.sorted { $0.id < $1.id }
    } else { reading.limitations.append(L10n.text("Per-core CPU counters unavailable.")) }
    if hardware.valid & UInt32(NB_HARDWARE_GPU_VALID) != 0 {
        reading.gpus = []
        if let gpus = hardware.gpus {
            reading.gpus = (0..<Int(hardware.gpu_count)).map { index in
                let gpu = gpus[index]
                return GPUSample(id: "ioreg:\(gpu.registry_id)", name: cleanText(nativeString(gpu.name)),
                                 coreCount: gpu.core_count > 0 ? Int(gpu.core_count) : nil,
                                 utilizationPercent: gpu.valid & UInt32(NB_GPU_DEVICE_VALID) != 0 ? gpu.utilization_percent : nil,
                                 rendererUtilizationPercent: gpu.valid & UInt32(NB_GPU_RENDERER_VALID) != 0 ? gpu.renderer_percent : nil,
                                 tilerUtilizationPercent: gpu.valid & UInt32(NB_GPU_TILER_VALID) != 0 ? gpu.tiler_percent : nil)
            }.sorted { $0.id < $1.id }
        }
    } else { reading.limitations.append(L10n.text("GPU device list unavailable or incomplete.")) }
    reading.limitations.append(L10n.text("GPU: device-wide totals reported by the driver, not per-core or per-process usage. Missing driver measurements are not zero."))
}

private func nativeString<T>(_ value: T) -> String {
    withUnsafeBytes(of: value) { buffer in
        String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

private func isDenied(_ error: Int32) -> Bool { error == EPERM || error == EACCES }
