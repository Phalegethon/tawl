import Foundation

/// Discard terminal escape sequences (including OSC payloads), then normalize controls.
public func cleanText(_ text: String) -> String {
    enum State { case plain, escape, csi, osc, oscEscape }
    var state = State.plain
    var result = ""
    for scalar in text.unicodeScalars {
        let v = scalar.value
        switch state {
        case .plain:
            if v == 27 { state = .escape }
            else if v == 0x9b { state = .csi }
            else if v == 0x9d { state = .osc }
            else if v < 32 || (127...159).contains(v) { result.append(" ") }
            else if scalar.properties.generalCategory != .format { result.unicodeScalars.append(scalar) }
        case .escape:
            if v == 91 { state = .csi }
            else if v == 93 || v == 80 || v == 94 || v == 95 { state = .osc }
            else { state = .plain }
        case .csi:
            if (0x40...0x7e).contains(v) { state = .plain }
        case .osc:
            if v == 7 || v == 0x9c { state = .plain }
            else if v == 27 { state = .oscEscape }
        case .oscEscape: state = v == 92 ? .plain : .osc
        }
    }
    return result.trimmingCharacters(in: .whitespaces)
}
public func formatBytes(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    var n = Double(value)
    let units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var i = 0
    while n >= 1024 && i < units.count - 1 { n /= 1024; i += 1 }
    return i == 0 ? "\(value) B" : String(format: "%.1f %@", n, units[i])
}
public func formatRate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0, value < Double(UInt64.max) else { return "—" }
    return formatBytes(UInt64(value)) + "/s"
}
public func pressureLabel(_ pressure: Pressure) -> String {
    switch pressure {
    case .normal: return L10n.text("Normal")
    case .warning: return L10n.text("Pressure")
    case .critical: return L10n.text("Critical")
    case .unknown: return L10n.text("Unavailable")
    }
}
