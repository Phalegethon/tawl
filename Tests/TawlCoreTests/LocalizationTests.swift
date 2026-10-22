import XCTest
@testable import TawlCore

final class LocalizationTests: XCTestCase {
    func testEnglishDefaultIgnoresOperatingSystemLocale() throws {
        XCTAssertEqual(try CLIOptions.parse([], environment: ["LANG": "tr_TR.UTF-8", "LC_ALL": "tr_TR"]).language, .english)
        XCTAssertEqual(L10n.withLanguage(.english) { L10n.text("Recording complete: \(3) samples.") }, "Recording complete: 3 samples.")
    }

    func testLanguageSelectionPrecedenceAcrossCommands() throws {
        let commands = [[], ["watch"], ["status"], ["record", "--output", "session.tawl"],
                        ["report", "session.tawl"], ["update"], ["update", "check"], ["--help"], ["--version"]]
        for command in commands {
            XCTAssertEqual(try CLIOptions.parse(command, environment: ["TAWL_LANG": "tr"]).language, .turkish)
            XCTAssertEqual(try CLIOptions.parse(["--lang", "en"] + command, environment: ["TAWL_LANG": "tr"]).language, .english)
            XCTAssertEqual(try CLIOptions.parse(command + ["--lang=tr"], environment: ["TAWL_LANG": "en"]).language, .turkish)
        }
        XCTAssertEqual(try CLIOptions.parse(["--lang", " EN "], environment: ["TAWL_LANG": "invalid"]).language, .english)
        XCTAssertEqual(try CLIOptions.parse([], environment: ["TAWL_LANG": "TR"]).language, .turkish)
    }

    func testInvalidLanguageAndOptionsFailClearly() {
        for args in [["--lang"], ["--lang="], ["--lang", "fr"], ["--lang", "--help"],
                     ["--lang", "en", "--lang=tr"], ["--lang=tr", "status", "--unknown"]] {
            XCTAssertThrowsError(try CLIOptions.parse(args, environment: [:]), "\(args)")
        }
        XCTAssertThrowsError(try CLIOptions.parse([], environment: ["TAWL_LANG": "invalid"]))
        XCTAssertThrowsError(try CLIOptions.parse(["--lang=tr", "status", "--unknown"], environment: [:])) {
            XCTAssertEqual(String(describing: $0), TurkishCLI.strings["Invalid or repeated option: "]! + "--unknown")
        }
    }

    func testInterpolationPreservesNamesPathsAndPlaceholderLikeData() {
        let payload = "Browser {0} %s /tmp/<file>&\"\nnew-line"
        let message: LocalizedMessage = "Language must be en or tr: \(payload)"
        XCTAssertEqual(L10n.render(message, language: .english), "Language must be en or tr: " + payload)
        let expectedPrefix = TurkishCLI.strings[message.key]!.replacingOccurrences(of: "{0}", with: "")
        XCTAssertEqual(L10n.render(message, language: .turkish), expectedPrefix + payload)
        let unknown: LocalizedMessage = "Uncatalogued \(payload)"
        XCTAssertEqual(L10n.render(unknown, language: .turkish), "Uncatalogued " + payload)
    }

    func testScopeRestoresLanguageAfterNestedOverrideAndThrow() throws {
        enum FixtureError: Error { case expected }
        try L10n.withLanguage(.english) {
            XCTAssertThrowsError(try L10n.withLanguage(.turkish) {
                XCTAssertEqual(L10n.language, .turkish)
                throw FixtureError.expected
            })
            XCTAssertEqual(L10n.language, .english)
        }
    }

    func testCatalogsHaveCompatiblePlaceholdersAndConsistentDuplicates() {
        var seen: [String: String] = [:]
        for catalog in L10n.catalogs {
            for (key, translation) in catalog {
                XCTAssertFalse(translation.isEmpty, key)
                XCTAssertEqual(L10n.placeholders(key), L10n.placeholders(translation), key)
                if let previous = seen[key] { XCTAssertEqual(previous, translation, "Conflicting translation: \(key)") }
                seen[key] = translation
            }
        }
        XCTAssertGreaterThan(seen.count, 600)
    }
}
