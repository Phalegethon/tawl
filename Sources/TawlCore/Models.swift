import Foundation

public enum Pressure: String, Codable { case normal, warning, critical, unknown }
public enum Grouping: String, Codable, CaseIterable { case application, project, category }

public struct CPUTicks {
    public var busy: UInt64
    public var total: UInt64
    public init(busy: UInt64, total: UInt64) { self.busy = busy; self.total = total }
}

/// In-memory OS data. Never serialize raw paths or command arguments.
public struct RawProcess {
    public var pid: Int32
    public var parentPID: Int32
    public var startedAt: UInt64
    public var name: String
    public var executablePath: String?
    public var workingDirectory: String?
    public var cpuNanoseconds: UInt64?
    public var footprintBytes: UInt64?
    public var residentBytes: UInt64?
    public var diskReadBytes: UInt64?
    public var diskWriteBytes: UInt64?
    public var isOwnedByCurrentUser: Bool?
    public var id: String { "\(pid):\(startedAt)" }
    public init(pid: Int32, parentPID: Int32 = 0, startedAt: UInt64, name: String,
                executablePath: String? = nil, workingDirectory: String? = nil,
                cpuNanoseconds: UInt64? = nil, footprintBytes: UInt64? = nil) {
        self.pid = pid; self.parentPID = parentPID; self.startedAt = startedAt; self.name = name
        self.executablePath = executablePath; self.workingDirectory = workingDirectory
        self.cpuNanoseconds = cpuNanoseconds; self.footprintBytes = footprintBytes
    }
}

public struct RawReading {
    public var timestamp: Date
    public var monotonicTime: Double
    public var cpuTicks: CPUTicks?
    public var cpuCores: [RawCPUCore]?
    public var gpus: [GPUSample]?
    public var logicalCPUCount: Int = 0
    public var memoryTotalBytes: UInt64 = 0
    public var pressure: Pressure = .unknown
    public var compressedBytes: UInt64?
    public var swapUsedBytes: UInt64?
    public var swapInBytes: UInt64?
    public var swapOutBytes: UInt64?
    public var networkInBytes: UInt64?
    public var networkOutBytes: UInt64?
    public var diskReadBytes: UInt64?
    public var diskWriteBytes: UInt64?
    public var totalProcessCount: Int = 0
    public var unreadableProcessCount: Int = 0
    public var processes: [RawProcess] = []
    public var limitations: [String] = []
    public init(timestamp: Date = Date(), monotonicTime: Double = ProcessInfo.processInfo.systemUptime) {
        self.timestamp = timestamp; self.monotonicTime = monotonicTime
    }
}

public struct ProcessSample: Codable, Identifiable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var applicationID: String
    public var applicationName: String
    public var projectID: String?
    public var projectName: String?
    public var projectEvidence: String?
    public var cpuCores: Double?
    public var footprintBytes: UInt64?
    public var memoryDeltaBytes: Int64?
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    /// Elapsed wall-clock age from the OS start timestamp; absent in older recordings.
    public var ageSeconds: Double?
    /// True only for an identified, non-system application process owned by this user.
    public var canReviewClosure: Bool?
}

/// Safe-to-record measurement: no executable path, cwd, argv, env or network endpoints.
public struct Snapshot: Codable {
    public var timestamp: Date
    public var monotonicTime: Double
    public var intervalSeconds: Double?
    public var cpuPercent: Double?
    /// Optional for older recordings and unavailable hardware collectors.
    public var cpuCores: [CPUCoreSample]?
    public var gpus: [GPUSample]?
    public var logicalCPUCount: Int = 0
    public var memoryTotalBytes: UInt64 = 0
    public var pressure: Pressure = .unknown
    public var compressedBytes: UInt64?
    public var swapUsedBytes: UInt64?
    public var swapInBytesPerSecond: Double?
    public var swapOutBytesPerSecond: Double?
    public var networkInBytesPerSecond: Double?
    public var networkOutBytesPerSecond: Double?
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    public var totalProcessCount: Int = 0
    public var unreadableProcessCount: Int = 0
    public var processes: [ProcessSample] = []
    public var limitations: [String] = []
    public init(timestamp: Date = Date(), monotonicTime: Double = 0) {
        self.timestamp = timestamp; self.monotonicTime = monotonicTime
    }
}

public struct Workload: Identifiable {
    public var id: String
    public var name: String
    public var memberIDs: [String]
    public var cpuCores: Double?
    public var footprintBytes: UInt64?
    public var memoryDeltaBytes: Int64?
    public var unknownCPUCount: Int
    public var unknownMemoryCount: Int
}

public struct Finding: Codable {
    public var code: String
    public var severity: String
    public var title: String
    public var detail: String
    public var start: Date
    public var end: Date
    public var relatedWorkloadIDs: [String]
}

public struct EventMarker: Codable {
    public var timestamp: Date
    public var label: String
    public init(timestamp: Date = Date(), label: String = L10n.text("Slowdown marker")) {
        self.timestamp = timestamp; self.label = label
    }
}
