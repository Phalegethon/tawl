import Foundation

public enum AppLanguage: String, CaseIterable {
    case english = "en"
    case turkish = "tr"

    public var locale: Locale {
        Locale(identifier: self == .english ? "en_US_POSIX" : "tr_TR")
    }
}

/// Keeps values separate from message keys: names and paths are never translated.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

public enum L10n {
    private static let lock = NSLock()
    private static var configuredLanguage: AppLanguage = .english
    private static let threadKey = "tawl.localization.language"
    private static let tokens = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
    static let catalogs = [TurkishCLI.strings, TurkishCore.strings, TurkishTerminal.strings, TurkishUpdates.strings]
    static let turkishCatalog = catalogs.reduce(into: [String: String]()) { result, catalog in
        result.merge(catalog, uniquingKeysWith: { first, _ in first })
    }

    public static var language: AppLanguage {
        if let override = Thread.current.threadDictionary[threadKey] as? String,
           let language = AppLanguage(rawValue: override) { return language }
        lock.lock(); defer { lock.unlock() }
        return configuredLanguage
    }
    public static var locale: Locale { language.locale }
    public static func configure(_ language: AppLanguage) {
        lock.lock(); defer { lock.unlock() }
        configuredLanguage = language
    }
    /// Scoped overrides do not leak between independent threads or test cases.
    public static func withLanguage<T>(_ language: AppLanguage, _ body: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let prior = dictionary[threadKey]
        dictionary[threadKey] = language.rawValue
        defer { if let prior { dictionary[threadKey] = prior } else { dictionary.removeObject(forKey: threadKey) } }
        return try body()
    }
    public static func text(_ message: LocalizedMessage) -> String {
        render(message, language: language)
    }
    /// Lookup for a static key selected at runtime, never for user-supplied text.
    public static func string(_ key: String) -> String {
        text(LocalizedMessage(stringLiteral: key))
    }
    static func render(_ message: LocalizedMessage, language: AppLanguage) -> String {
        let candidate = language == .turkish ? turkishCatalog[message.key] : nil
        let template = candidate.flatMap { placeholders($0) == placeholders(message.key) ? $0 : nil } ?? message.key
        var result = ""
        var cursor = template.startIndex
        for match in tokens.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let range = Range(match.range, in: template),
                  let numberRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[numberRange]), message.arguments.indices.contains(index) else { continue }
            result += template[cursor..<range.lowerBound]
            result += message.arguments[index]
            cursor = range.upperBound
        }
        result += template[cursor...]
        return result
    }
    static func placeholders(_ text: String) -> [String] {
        tokens.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
    }
}
