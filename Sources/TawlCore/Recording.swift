import Foundation
import Darwin

/// Estimated encoded bytes plus a small per-entry allowance; this is not an RSS measurement.
public final class SessionHistory {
    public private(set) var snapshots: [Snapshot] = []
    public private(set) var markers: [EventMarker] = []
    public private(set) var estimatedBytes = 0
    private let maxDuration: TimeInterval
    private let maxBytes: Int
    private var newestTime: Double?
    private var latestSnapshotClock: (timestamp: Date, monotonic: Double)?
    private var entries: [Entry] = []

    private struct Entry {
        var time: Double
        var bytes: Int
        var snapshot: Snapshot?
        var marker: EventMarker?
    }

    public init(maxDuration: TimeInterval = 1800, maxBytes: Int = 64 * 1024 * 1024) {
        self.maxDuration = maxDuration.isFinite ? max(0, maxDuration) : 1800
        self.maxBytes = max(0, maxBytes)
    }

    public func append(_ snapshot: Snapshot) {
        guard (try? validate(snapshot)) != nil,
              let encoded = try? JSONEncoder().encode(snapshot) else { return }
        if let clock = latestSnapshotClock {
            guard snapshot.monotonicTime > clock.monotonic else { return }
        } else {
            // Before the first measurement, only wall time exists. Rebase those early markers
            // once, then keep the entire session on the monotonic sampling timeline.
            for index in entries.indices {
                if let marker = entries[index].marker {
                    entries[index].time = snapshot.monotonicTime + min(0, marker.timestamp.timeIntervalSince(snapshot.timestamp))
                }
            }
            newestTime = snapshot.monotonicTime
        }
        latestSnapshotClock = (snapshot.timestamp, snapshot.monotonicTime)
        insert(Entry(time: snapshot.monotonicTime, bytes: encoded.count + 64, snapshot: snapshot))
    }

    public func mark(_ marker: EventMarker) {
        guard marker.timestamp.timeIntervalSinceReferenceDate.isFinite,
              let encoded = try? JSONEncoder().encode(marker) else { return }
        // Event timestamps remain exact in the model/file. Retention uses the latest sampling
        // instant so a wall-clock adjustment cannot evict or indefinitely retain history.
        let time = latestSnapshotClock?.monotonic ?? marker.timestamp.timeIntervalSinceReferenceDate
        insert(Entry(time: time, bytes: encoded.count + 64, marker: marker))
    }

    public func last(seconds: Double) -> [Snapshot] {
        guard seconds.isFinite, seconds >= 0, let latest = snapshots.last else { return [] }
        let cutoff = latest.monotonicTime - seconds
        return snapshots.filter { $0.monotonicTime >= cutoff }
    }

    private func insert(_ entry: Entry) {
        newestTime = max(newestTime ?? entry.time, entry.time)
        if entry.bytes <= maxBytes {
            // Normally append-only; sorted insertion keeps late markers from invalidating eviction.
            let position = entries.firstIndex { $0.time > entry.time } ?? entries.endIndex
            entries.insert(entry, at: position)
            estimatedBytes += entry.bytes
        }
        let cutoff = newestTime! - maxDuration
        var removeCount = 0
        while removeCount < entries.count &&
                (entries[removeCount].time < cutoff || estimatedBytes > maxBytes) {
            estimatedBytes -= entries[removeCount].bytes
            removeCount += 1
        }
        if removeCount > 0 { entries.removeFirst(removeCount) }
        snapshots = entries.compactMap(\.snapshot)
        markers = entries.compactMap(\.marker)
    }
}

public struct Recording {
    public var snapshots: [Snapshot]
    public var markers: [EventMarker]
    public var warnings: [String]
}

public enum RecordingError: Error, LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidRow(Int, String)
    case invalidSample(String)
    case sizeLimit(Int)
    case lineTooLong(Int)
    case closed
    case notRegularFile
    case io(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Geçerli bir TAWL kayıt başlığı bulunamadı."
        case .unsupportedVersion(let version): return "Kayıt sürümü desteklenmiyor: \(version). Desteklenen sürüm: 1."
        case .invalidRow(let line, let reason): return "Kayıt satırı \(line) geçersiz: \(reason)"
        case .invalidSample(let reason): return "Geçersiz ölçüm: \(reason)"
        case .sizeLimit(let limit): return "Kayıt boyut sınırına ulaşıldı (\(limit) bayt); kayıt durdu."
        case .lineTooLong(let line): return "Kayıt satırı \(line) izin verilen 8 MiB sınırını aşıyor."
        case .closed: return "Kayıt dosyası kapalı veya yazım durduruldu."
        case .notRegularFile: return "Kayıt için normal bir dosya gerekli."
        case .io(let operation, let code): return "Kayıt \(operation) hatası: \(String(cString: strerror(code)))."
        }
    }
}

private enum RecordingLimits {
    static let fileBytes = 100 * 1024 * 1024
    static let lineBytes = 8 * 1024 * 1024
}

private struct RecordRow: Codable {
    var type: String
    var format: String?
    var version: Int?
    var snapshot: Snapshot?
    var marker: EventMarker?
}

/// One foreground writer per recording. Creation is atomic and never replaces an existing target.
public final class RecordingWriter {
    private var descriptor: Int32 = -1
    private let maxBytes: Int
    private var writtenBytes = 0
    private var stopped = false
    private var lastMonotonicTime: Double?
    private let encoder = JSONEncoder()

    public init(url: URL, maxBytes: Int = 100 * 1024 * 1024) throws {
        self.maxBytes = min(maxBytes, RecordingLimits.fileBytes)
        let header = try encoder.encode(RecordRow(type: "header", format: "tawl", version: 1)) + Data([10])
        guard header.count <= self.maxBytes else { throw RecordingError.sizeLimit(self.maxBytes) }
        guard url.isFileURL else { throw RecordingError.notRegularFile }
        descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw RecordingError.io("oluşturma", errno) }
        do {
            guard fchmod(descriptor, 0o600) == 0 else { throw RecordingError.io("izin", errno) }
            try write(header)
        } catch {
            _ = Darwin.close(descriptor)
            descriptor = -1
            throw error
        }
    }

    public func append(_ snapshot: Snapshot) throws {
        try validate(snapshot)
        if let previous = lastMonotonicTime, snapshot.monotonicTime <= previous {
            throw RecordingError.invalidSample("örneklerin monotonik zamanı artmalı")
        }
        try appendRow(RecordRow(type: "snapshot", snapshot: snapshot))
        lastMonotonicTime = snapshot.monotonicTime
    }

    public func appendMarker(_ marker: EventMarker) throws {
        guard marker.timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw RecordingError.invalidSample("olay zamanı sonlu olmalı")
        }
        try appendRow(RecordRow(type: "marker", marker: marker))
    }

    public func close() throws {
        guard descriptor >= 0 else { return }
        let fd = descriptor
        descriptor = -1
        let syncError = fsync(fd) == 0 ? nil : errno
        let closeError = Darwin.close(fd) == 0 ? nil : errno
        if let code = syncError ?? closeError { throw RecordingError.io("kapatma", code) }
    }

    deinit { if descriptor >= 0 { _ = Darwin.close(descriptor) } }

    private func appendRow(_ row: RecordRow) throws {
        guard descriptor >= 0, !stopped else { throw RecordingError.closed }
        let data = try encoder.encode(row)
        guard data.count <= RecordingLimits.lineBytes else {
            stopped = true
            throw RecordingError.lineTooLong(0)
        }
        try write(data + Data([10]))
    }

    private func write(_ data: Data) throws {
        guard descriptor >= 0, !stopped else { throw RecordingError.closed }
        guard data.count <= maxBytes - writtenBytes else {
            stopped = true
            throw RecordingError.sizeLimit(maxBytes)
        }
        do {
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < data.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw RecordingError.io("yazma", count == 0 ? EIO : errno) }
                    offset += count
                }
            }
            writtenBytes += data.count
        } catch {
            stopped = true
            // A normal I/O failure should leave the previous complete prefix where possible.
            // Power loss can still leave a tail; the reader reports and skips only that tail.
            _ = ftruncate(descriptor, off_t(writtenBytes))
            throw error
        }
    }
}

public enum RecordingReader {
    public static func read(url: URL) throws -> Recording {
        guard url.isFileURL else { throw RecordingError.notRegularFile }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw RecordingError.io("okuma", errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw RecordingError.io("dosya bilgisi", errno) }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw RecordingError.notRegularFile }
        guard metadata.st_size <= RecordingLimits.fileBytes else { throw RecordingError.sizeLimit(RecordingLimits.fileBytes) }

        let decoder = JSONDecoder()
        var recording = Recording(snapshots: [], markers: [], warnings: [])
        var pending = Data()
        var totalBytes = 0
        var line = 0
        var hasHeader = false

        func consume(_ data: Data, finalUnterminated: Bool) throws {
            line += 1
            let row: RecordRow
            do { row = try decoder.decode(RecordRow.self, from: data) }
            catch {
                if hasHeader && finalUnterminated && isIncompleteJSON(data) {
                    recording.warnings.append("Son kayıt satırı eksik; önceki tamamlanmış kayıtlar okundu.")
                    return
                }
                throw RecordingError.invalidRow(line, "JSON veya satır şeması bozuk")
            }
            if !hasHeader {
                // The v1 payload is unchanged; recordings made before the rename remain readable.
                guard row.type == "header", (row.format == "tawl" || row.format == "nabiz"), let version = row.version,
                      row.snapshot == nil, row.marker == nil else { throw RecordingError.invalidFormat }
                guard version == 1 else { throw RecordingError.unsupportedVersion(version) }
                hasHeader = true
                return
            }
            guard row.format == nil, row.version == nil else {
                throw RecordingError.invalidRow(line, "beklenmeyen başlık alanı")
            }
            switch row.type {
            case "snapshot":
                guard let snapshot = row.snapshot, row.marker == nil else {
                    throw RecordingError.invalidRow(line, "ölçüm eksik veya çelişkili")
                }
                do { try validate(snapshot) }
                catch { throw RecordingError.invalidRow(line, error.localizedDescription) }
                if let previous = recording.snapshots.last, snapshot.monotonicTime <= previous.monotonicTime {
                    throw RecordingError.invalidRow(line, "örneklerin monotonik zamanı artmalı")
                }
                recording.snapshots.append(snapshot)
            case "marker":
                guard let marker = row.marker, row.snapshot == nil,
                      marker.timestamp.timeIntervalSinceReferenceDate.isFinite else {
                    throw RecordingError.invalidRow(line, "olay veya zamanı geçersiz")
                }
                recording.markers.append(marker)
            default: throw RecordingError.invalidRow(line, "bilinmeyen satır türü")
            }
        }

        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            totalBytes += chunk.count
            guard totalBytes <= RecordingLimits.fileBytes else { throw RecordingError.sizeLimit(RecordingLimits.fileBytes) }
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let end = chunk[start...].firstIndex(of: 10) ?? chunk.endIndex
                guard end - start <= RecordingLimits.lineBytes - pending.count else {
                    throw RecordingError.lineTooLong(line + 1)
                }
                pending.append(chunk[start..<end])
                if end < chunk.endIndex {
                    try consume(pending, finalUnterminated: false)
                    pending.removeAll(keepingCapacity: true)
                    start = end + 1
                } else { start = end }
            }
        }
        if !pending.isEmpty { try consume(pending, finalUnterminated: true) }
        guard hasHeader else { throw RecordingError.invalidFormat }
        return recording
    }

    private static func isIncompleteJSON(_ data: Data) -> Bool {
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return false // Valid JSON with invalid schema or numeric values is corruption, not truncation.
        } catch {
            // Foundation identifies lexical EOF separately from invalid tokens. Do not treat every
            // decoder error on a final line as an interrupted write.
            let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? ""
            return reason.contains("Unexpected end of file") || reason.contains("Unterminated string") || reason.contains("followed by EoF")
        }
    }
}

private func validate(_ snapshot: Snapshot) throws {
    func nonnegative(_ number: Double?) -> Bool { number.map { $0.isFinite && $0 >= 0 } ?? true }
    guard snapshot.timestamp.timeIntervalSinceReferenceDate.isFinite,
          nonnegative(snapshot.monotonicTime),
          snapshot.intervalSeconds.map({ $0.isFinite && $0 > 0 }) ?? true else {
        throw RecordingError.invalidSample("zaman veya örnekleme aralığı geçersiz")
    }
    guard nonnegative(snapshot.cpuPercent), snapshot.cpuPercent.map({ $0 <= 100 }) ?? true,
          snapshot.logicalCPUCount >= 0, snapshot.totalProcessCount >= 0, snapshot.unreadableProcessCount >= 0 else {
        throw RecordingError.invalidSample("CPU değeri veya süreç sayısı geçersiz")
    }
    if let cores = snapshot.cpuCores {
        guard cores.count <= HardwareLimits.cpuCount,
              Set(cores.map(\.id)).count == cores.count,
              cores.allSatisfy({ (0...HardwareLimits.cpuID).contains($0.id) && HardwareLimits.percentage($0.utilizationPercent) }) else {
            throw RecordingError.invalidSample("CPU çekirdek kimliği, sayısı veya kullanım değeri geçersiz")
        }
    }
    if let gpus = snapshot.gpus {
        guard gpus.count <= HardwareLimits.gpuCount, Set(gpus.map(\.id)).count == gpus.count,
              gpus.allSatisfy({ gpu in
                  !gpu.id.isEmpty && gpu.id.utf8.count <= 128 && !gpu.name.isEmpty && gpu.name.utf8.count <= 1024 &&
                  (gpu.coreCount.map { (1...HardwareLimits.gpuCoreCount).contains($0) } ?? true) &&
                  HardwareLimits.percentage(gpu.utilizationPercent) &&
                  HardwareLimits.percentage(gpu.rendererUtilizationPercent) && HardwareLimits.percentage(gpu.tilerUtilizationPercent)
              }) else {
            throw RecordingError.invalidSample("GPU kimliği, sayısı veya kullanım değeri geçersiz")
        }
    }
    let rates = [snapshot.swapInBytesPerSecond, snapshot.swapOutBytesPerSecond,
                 snapshot.networkInBytesPerSecond, snapshot.networkOutBytesPerSecond,
                 snapshot.diskReadBytesPerSecond, snapshot.diskWriteBytesPerSecond]
    guard rates.allSatisfy(nonnegative), snapshot.processes.allSatisfy({
        nonnegative($0.cpuCores) && nonnegative($0.diskReadBytesPerSecond) && nonnegative($0.diskWriteBytesPerSecond)
    }) else { throw RecordingError.invalidSample("hız ölçümleri sonlu ve negatif olmayan değerler olmalı") }
}
