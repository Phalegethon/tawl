import Foundation

public enum CPUCoreKind: String, Codable { case efficiency, performance, unknown }

/// A logical processor's busy time, not its relative computing throughput.
public struct CPUCoreSample: Codable, Equatable, Identifiable {
    public var id: Int
    public var kind: CPUCoreKind
    public var utilizationPercent: Double?
    public init(id: Int, kind: CPUCoreKind, utilizationPercent: Double?) {
        self.id = id; self.kind = kind; self.utilizationPercent = utilizationPercent
    }
}

/// Device-wide driver telemetry. Core count is hardware metadata, not an active-core count.
public struct GPUSample: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var coreCount: Int?
    public var utilizationPercent: Double?
    public var rendererUtilizationPercent: Double?
    public var tilerUtilizationPercent: Double?
    public init(id: String, name: String, coreCount: Int? = nil, utilizationPercent: Double?,
                rendererUtilizationPercent: Double? = nil, tilerUtilizationPercent: Double? = nil) {
        self.id = id; self.name = name; self.coreCount = coreCount
        self.utilizationPercent = utilizationPercent
        self.rendererUtilizationPercent = rendererUtilizationPercent
        self.tilerUtilizationPercent = tilerUtilizationPercent
    }
}

public struct RawCPUCore {
    public var id: Int
    public var kind: CPUCoreKind
    public var user: UInt32
    public var system: UInt32
    public var nice: UInt32
    public var idle: UInt32
    public init(id: Int, kind: CPUCoreKind = .unknown, user: UInt32, system: UInt32, nice: UInt32 = 0, idle: UInt32) {
        self.id = id; self.kind = kind; self.user = user; self.system = system; self.nice = nice; self.idle = idle
    }
}

enum HardwareLimits {
    static let cpuCount = 1024
    static let cpuID = 4095
    static let gpuCount = 16
    static let gpuCoreCount = 65536
    static func percentage(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...100).contains($0) } ?? true
    }
}
