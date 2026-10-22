import Foundation
import CTawl

public protocol ProcessClosureControlling: AnyObject {
    /// Read-only preparation. A message means no native ticket was retained.
    func prepare(_ intent: ProcessClosureIntent) -> String?
    func submit(_ intent: ProcessClosureIntent) -> ProcessClosureSubmission
    func observe(_ intent: ProcessClosureIntent) -> ProcessClosureObservation
    func clear()
}

/// The only adapter that sends a process signal. It operates on one short-lived
/// native audit token after a product-level confirmation has been consumed.
public final class NativeProcessController: ProcessClosureControlling {
    private var ticket: nb_process_control_ticket?
    private var boundIntent: ProcessClosureIntent?

    public init() {}

    public func prepare(_ intent: ProcessClosureIntent) -> String? {
        clear()
        var candidate = nb_process_control_ticket()
        let result = nb_process_control_prepare(intent.pid, intent.startedAt, &candidate)
        guard result == NB_CONTROL_OK else { return Self.message(for: result) }
        let path = Self.string(from: candidate.executable_path)
        guard !path.isEmpty else { return "Uygulamanın çalıştırılabilir dosyası doğrulanamadı." }
        let raw = RawProcess(pid: candidate.pid, parentPID: candidate.parent_pid,
                             startedAt: candidate.start_microseconds,
                             name: Self.string(from: candidate.name), executablePath: path)
        let identity = Attributor().identify(raw, among: [])
        guard identity.applicationID == intent.applicationID,
              cleanText(identity.applicationName) == intent.applicationName else {
            return "Canlı süreç farklı bir uygulamaya ait; kapatma hazırlığı iptal edildi."
        }
        ticket = candidate
        boundIntent = intent
        return nil
    }

    public func submit(_ intent: ProcessClosureIntent) -> ProcessClosureSubmission {
        guard matches(intent), var candidate = ticket else {
            return .rejected("Bu süreç için doğrulanmış bir kapatma hazırlığı yok.")
        }
        let result = nb_process_control_terminate(&candidate)
        ticket = candidate
        return result == NB_CONTROL_OK ? .sent : .rejected(Self.message(for: result))
    }

    public func observe(_ intent: ProcessClosureIntent) -> ProcessClosureObservation {
        guard matches(intent), var candidate = ticket else { return .unreadable }
        switch Int(nb_process_control_status(&candidate)) {
        case NB_PROCESS_ALIVE: return .alive
        case NB_PROCESS_EXITED: return .exited
        case NB_PROCESS_REPLACED: return .replaced
        default: return .unreadable
        }
    }

    public func clear() { ticket = nil; boundIntent = nil }

    private func matches(_ intent: ProcessClosureIntent) -> Bool {
        guard let bound = boundIntent else { return false }
        return bound.processID == intent.processID && bound.pid == intent.pid &&
            bound.startedAt == intent.startedAt && bound.applicationID == intent.applicationID &&
            bound.applicationName == intent.applicationName && bound.createdAt == intent.createdAt
    }

    private static func string<T>(from value: T) -> String {
        withUnsafeBytes(of: value) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func message(for code: Int32) -> String {
        switch Int(code) {
        case NB_CONTROL_ANCESTRY_UNAVAILABLE:
            return "Terminalin üst süreç zinciri doğrulanamadı; kapatma hazırlığı durduruldu. Hedefin korunan bir süreç olduğu belirlenmedi."
        case NB_CONTROL_PROTECTED:
            return "Bu süreç korunuyor: sistem, altyapı, başka kullanıcı veya terminalin kendi süreci."
        case NB_CONTROL_CHANGED:
            return "Süreç kapanmış veya kimliği değişmiş; kapatma isteği gönderilmedi."
        case NB_CONTROL_EXPIRED:
            return "Onayın 30 saniyelik süresi doldu; süreci yeniden seç."
        case NB_CONTROL_ALREADY_USED:
            return "Bu onay daha önce işlendi; yeniden istek gönderilmedi."
        case NB_CONTROL_DENIED:
            return "macOS kapatma isteğine izin vermedi."
        case NB_CONTROL_UNAVAILABLE:
            return "Sürecin canlı kimliği doğrulanamadı; kapatma isteği gönderilmedi."
        case NB_CONTROL_SIGNAL_FAILED:
            return "macOS kapatma isteğini kabul etmedi."
        default:
            return "Kapatma isteği geçersiz; süreci yeniden seç."
        }
    }
}
