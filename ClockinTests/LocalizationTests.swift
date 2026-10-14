import Foundation
import Testing
@testable import Clockin

/// Every string has a Norwegian translation, with the same blanks to fill,
/// and the app ships it.
struct LocalizationTests {
    /// The repository, from this file's place in it (tests run on the Mac's simulator).
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let catalogs = ["Shared/Localizable.xcstrings", "Clockin/InfoPlist.xcstrings",
                           "Clockin/Intents/AppShortcuts.xcstrings"]

    struct Entry {
        var key: String
        var english: [String]
        var norwegian: [String]?
    }

    /// Each key to translate, with its English and Norwegian values (one, or each plural form).
    static func entries(_ path: String) throws -> [Entry] {
        let data = try Data(contentsOf: root.appending(path: path))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        return strings.compactMap { key, entry in
            guard entry["shouldTranslate"] as? Bool != false else { return nil }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            return Entry(key: key, english: values(localizations["en"]) ?? [key],
                         norwegian: values(localizations["nb"]))
        }
    }

    private static func values(_ localization: Any?) -> [String]? {
        guard let localization = localization as? [String: Any] else { return nil }
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        if let variations = localization["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: [String: Any]] {
            return ["one", "other"].compactMap { (plural[$0]?["stringUnit"] as? [String: Any])?["value"] as? String }
        }
        return nil
    }

    /// The blanks a string has, by type, in order of their positions.
    static func placeholders(_ text: String) -> [String] {
        let pattern = /%(?:(\d+)\$)?(lld|ld|d|@|f|\.\d+f)/
        let found = text.matches(of: pattern).enumerated().map { index, match in
            (Int(match.output.1 ?? "") ?? index + 1, String(match.output.2))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    @Test(arguments: catalogs)
    func everyStringIsInNorwegian(_ path: String) throws {
        let entries = try Self.entries(path)
        #expect(!entries.isEmpty)
        for entry in entries {
            let norwegian = try #require(entry.norwegian, "\(path): no nb for \"\(entry.key)\"")
            #expect(norwegian.count == entry.english.count, "\(path): \"\(entry.key)\" is missing a plural form")
            #expect(norwegian.allSatisfy { !$0.isEmpty }, "\(path): \"\(entry.key)\" is empty in nb")
        }
    }

    @Test(arguments: catalogs)
    func norwegianKeepsTheBlanks(_ path: String) throws {
        for entry in try Self.entries(path) {
            guard let norwegian = entry.norwegian else { continue }
            for (english, translated) in zip(entry.english, norwegian) {
                #expect(Self.placeholders(english) == Self.placeholders(translated),
                        "\(path): \"\(entry.key)\" → \"\(translated)\"")
                // App Shortcuts phrases must name the app.
                if path.hasSuffix("AppShortcuts.xcstrings") { #expect(translated.contains("${applicationName}")) }
            }
        }
    }

    @Test func blanksAreReadInOrder() {
        #expect(Self.placeholders("Next: %1$@ · session %2$lld of %3$lld") == ["@", "lld", "lld"])
        #expect(Self.placeholders("%2$lld av %1$@") == ["@", "lld"])
    }

    @Test func theAppShipsNorwegian() throws {
        let bundle = Bundle(for: AppServices.self)
        #expect(bundle.localizations.contains("nb"))
        let path = try #require(bundle.path(forResource: "nb", ofType: "lproj"))
        let norwegian = try #require(Bundle(path: path))
        #expect(norwegian.localizedString(forKey: "Break's over", value: nil, table: nil) == "Pausen er over")
        #expect(norwegian.localizedString(forKey: "NSAlarmKitUsageDescription", value: nil, table: "InfoPlist")
            .contains("Clockin"))
    }
}
