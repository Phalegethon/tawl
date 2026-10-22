import Foundation
public struct CLIOptions {
    public var language: AppLanguage = .english
    public var command = "watch"
    public var sampleSeconds: Double = 3
    public var durationSeconds: Double = 60
    public var lastSeconds: Double?
    public var output: String?
    public var input: String?
    public var json = false
    public var help = false
    public var assumeYes = false
    public var noUpdateCheck = false
    public static func languageSelection(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> (language: AppLanguage, arguments: [String]) {
        var remaining: [String] = []
        var requested: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--lang" || argument.hasPrefix("--lang=") {
                guard requested == nil else { throw CLIError(L10n.text("--lang can only be specified once.")) }
                if argument == "--lang" {
                    index += 1
                    guard index < arguments.count, !arguments[index].hasPrefix("-") else { throw CLIError(L10n.text("--lang requires en or tr.")) }
                    requested = arguments[index]
                } else { requested = String(argument.dropFirst(7)) }
            } else { remaining.append(argument) }
            index += 1
        }
        let value = (requested ?? environment["TAWL_LANG"] ?? "en").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let language = AppLanguage(rawValue: value) else { throw CLIError(L10n.text("Language must be en or tr: \(cleanText(value))")) }
        return (language, remaining)
    }
    public static func parse(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CLIOptions {
        let selection = try languageSelection(arguments, environment: environment)
        return try L10n.withLanguage(selection.language) { try parseCommand(selection.arguments, language: selection.language) }
    }
    private static func parseCommand(_ arguments: [String], language: AppLanguage) throws -> CLIOptions {
        var result = CLIOptions()
        result.language = language
        if arguments == ["--help"] || arguments == ["-h"] { result.help = true; return result }
        if arguments == ["--version"] || arguments == ["version"] { result.command = "version"; return result }
        if arguments.first == "update" {
            let rest = Array(arguments.dropFirst())
            if rest == ["--help"] || rest == ["-h"] { result.help = true; return result }
            if rest == ["check"] || rest == ["--check"] { result.command = "update-check"; return result }
            guard rest.isEmpty || rest == ["--yes"] else { throw CLIError(L10n.text("Usage: tawl update [check | --check | --yes]")) }
            result.command = "update"; result.assumeYes = rest == ["--yes"]; return result
        }
        var args = arguments
        if let first = args.first, !first.hasPrefix("-") { result.command = args.removeFirst() }
        guard ["watch", "status", "record", "report"].contains(result.command) else { throw CLIError(L10n.text("Unknown command. Run tawl --help.")) }
        let allowed: [String: Set<String>] = [
            "watch": ["--record", "--no-update-check"], "status": ["--sample", "--json"],
            "record": ["--duration", "--output"], "report": ["--last", "--json"]]
        var seen: Set<String> = []
        while !args.isEmpty {
            let token = args.removeFirst()
            if token == "--help" || token == "-h" { result.help = true; return result }
            if result.command == "report", !token.hasPrefix("-"), result.input == nil { result.input = token; continue }
            guard allowed[result.command]!.contains(token), seen.insert(token).inserted else { throw CLIError(L10n.text("Invalid or repeated option: ") + cleanText(token)) }
            if token == "--json" { result.json = true; continue }
            if token == "--no-update-check" { result.noUpdateCheck = true; continue }
            guard !args.isEmpty, !args[0].hasPrefix("--") else { throw CLIError(L10n.text("Missing option value: ") + token) }
            let value = args.removeFirst()
            switch token {
            case "--record", "--output":
                guard !value.isEmpty else { throw CLIError(L10n.text("File path cannot be empty.")) }; result.output = value
            case "--sample": result.sampleSeconds = try duration(value, max: 10)
            case "--duration": result.durationSeconds = try duration(value, max: 86400)
            case "--last": result.lastSeconds = try duration(value, max: 86400)
            default: break
            }
        }
        if result.command == "record", result.output == nil { throw CLIError(L10n.text("record requires --output.")) }
        if result.command == "report", result.input == nil { throw CLIError(L10n.text("report requires a recording file.")) }
        return result
    }
    private static func duration(_ text: String, max: Double) throws -> Double {
        var number = text
        var multiplier = 1.0
        if let suffix = number.last, ["s", "m", "h"].contains(suffix) {
            number.removeLast(); multiplier = suffix == "h" ? 3600 : suffix == "m" ? 60 : 1
        }
        guard let value = Double(number), value.isFinite, value * multiplier >= 0.1, value * multiplier <= max else {
            throw CLIError(L10n.text("Duration must be between 0.1 and \(Int(max)) seconds (for example: 3s, 5m)."))
        }
        return value * multiplier
    }
}
public struct CLIError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
