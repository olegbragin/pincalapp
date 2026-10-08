//
//  PCLocalizationCatalogTests.swift
//  PinCalAppTests
//
//  Every package owns a `Localizable.xcstrings`, plus one in the app target. That is deliberate:
//  a package's catalog is tracked by Xcode against *that package's* target, so its keys are
//  referenced rather than reported as orphans — which is what the single app-level catalog was
//  doing for ~38 of them.
//
//  The catalog files are what a translator edits, and the thing that goes wrong with them is
//  invisible at runtime. An untranslated key falls through to its English source and renders as a
//  correct-looking English label. A dropped format specifier prints the sentence with a hole in
//  it. So these tests are the only place either is visible, and they check every catalog rather
//  than a fixed list — a hard-coded list is the failure that produced the orphan warnings in the
//  first place.
//

import Foundation
import Testing

@Suite("Localization catalogs")
struct PCLocalizationCatalogTests {
    /// The repository root, from this file: `…/pincalapp/PinCalAppTests/<this file>` → up two.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// A catalog that could not be found, or a root that isn't there. Thrown rather than
    /// tolerated: a test that finds nothing has checked nothing, and must not pass quietly.
    private struct CannotCheck: Error, CustomStringConvertible {
        let reason: String
        init(_ reason: String) {
            self.reason = reason
        }

        var description: String {
            "\(reason) — this test would otherwise pass without checking anything"
        }
    }

    /// Every catalog in the repository, as `(path, table)`.
    ///
    /// Discovered rather than listed, so a package gaining a catalog is covered with no edit here.
    private static func catalogs() throws -> [(path: String, table: [String: [String: String]])] {
        let root = repoRoot
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw CannotCheck("no repository root at \(root.path)")
        }
        let paths = try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".xcstrings") && !$0.contains("/.build/") }
            .sorted()
        guard !paths.isEmpty else {
            throw CannotCheck("no .xcstrings anywhere under \(root.path)")
        }
        return try paths.map { relative in
            let data = try Data(contentsOf: root.appendingPathComponent(relative))
            let json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any],
                "\(relative) is not a JSON object"
            )
            let strings = try #require(json["strings"] as? [String: Any], "\(relative) has no `strings`")
            var table: [String: [String: String]] = [:]
            for (key, entry) in strings {
                let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
                var values: [String: String] = [:]
                for (language, unit) in localizations {
                    if let value = (unit as? [String: Any])?["stringUnit"] as? [String: Any],
                       let text = value["value"] as? String
                    {
                        values[language] = text
                    }
                }
                table[key] = values
            }
            return (relative, table)
        }
    }

    private static func isFormat(_ key: String) -> Bool {
        key.contains("%")
    }

    @Test("Every catalog is readable and every key has an English source")
    func everyKeyHasEnglish() throws {
        for (path, table) in try Self.catalogs() {
            #expect(!table.isEmpty, "\(path) has no keys")
            for key in table.keys.sorted() {
                #expect(table[key]?["en"] != nil, "\(path): no English source for \(key)")
            }
        }
    }

    /// The check that stops Russian rotting, and the one the whole suite exists for.
    ///
    /// A missing `ru` entry is not detectable at runtime — the lookup falls through to English and
    /// the user sees a plausible label — so this is the only place it can be noticed.
    @Test("Every key in every catalog has a Russian translation")
    func everyKeyIsTranslatedIntoRussian() throws {
        var untranslated: [String] = []
        for (path, table) in try Self.catalogs() {
            for key in table.keys.sorted() {
                // `PinCal` is the product name and identical in both languages on purpose.
                guard key != "PinCal" else { continue }
                if (table[key]?["ru"] ?? key) == key {
                    untranslated.append("\(path): \(key)")
                }
            }
        }
        #expect(untranslated.isEmpty, "no Russian translation: \(untranslated)")
    }

    /// An empty value is how a half-finished translation reaches the user as a blank label, and it
    /// would pass the check above by *not* equalling its key.
    @Test("No translation is empty")
    func noTranslationIsEmpty() throws {
        var empty: [String] = []
        for (path, table) in try Self.catalogs() {
            for (key, values) in table {
                for (language, value) in values where value.trimmingCharacters(in: .whitespaces).isEmpty {
                    empty.append("\(path): \(key) [\(language)]")
                }
            }
        }
        #expect(empty.isEmpty, "empty translation: \(empty.sorted())")
    }

    /// A translation that drops its specifier produces a sentence with a hole in it.
    @Test("A translated format string keeps its specifiers")
    func translationsKeepTheirSpecifiers() throws {
        let specifiers = CharacterSet(charactersIn: "@lld")
        var lost: [String] = []
        for (path, table) in try Self.catalogs() {
            for (key, values) in table where Self.isFormat(key) {
                for (language, value) in values
                    where !value.unicodeScalars.contains(where: { specifiers.contains($0) })
                {
                    lost.append("\(path): \(key) → \(language)")
                }
            }
        }
        #expect(lost.isEmpty, "translation lost its specifier: \(lost.sorted())")
    }

    /// The mirror image: a key that is prose in English must not become a format in translation,
    /// or `String(format:)` looks for a placeholder that is not there and prints a stray `%@`.
    @Test("A translation never invents a format specifier")
    func translationsDoNotInventSpecifiers() throws {
        var invented: [String] = []
        for (path, table) in try Self.catalogs() {
            for (key, values) in table where !Self.isFormat(key) {
                if values.values.contains(where: { $0.contains("%") }) {
                    invented.append("\(path): \(key)")
                }
            }
        }
        #expect(invented.isEmpty, "non-format key translated with a specifier: \(invented.sorted())")
    }

    /// Both languages must agree on arity, because the call site decides that from the *English*
    /// text: `String(format: String(localized: .columns(n)), n)` is reached because the English
    /// key is a format. A key that is a format in English and prose in Russian prints the format
    /// string un-substituted.
    @Test("Both languages agree on which keys take arguments")
    func languagesAgreeOnArity() throws {
        var mismatched: [String] = []
        for (path, table) in try Self.catalogs() {
            for (key, values) in table
                where Self.isFormat(key) != values.values.contains(where: { Self.isFormat($0) })
            {
                mismatched.append("\(path): \(key)")
            }
        }
        #expect(mismatched.isEmpty, "format-ness differs between languages: \(mismatched.sorted())")
    }

    /// Russian reorders, so a reordered format string has to use positional specifiers.
    ///
    /// Nothing mechanical can tell "reordered" from "rewritten around the same order", so this is a
    /// narrow heuristic: a translation that *differs* from the English template and still uses bare
    /// `%@` is assumed to have moved its arguments. The one string in this project that does reorder is
    /// pinned by value so the expected answer is visible rather than inferred.
    @Test("Reordered format strings use positional specifiers")
    func reorderedFormatsArePositional() throws {
        var suspects: [String] = []
        for (path, table) in try Self.catalogs() {
            for (key, values) in table where Self.isFormat(key) {
                guard let english = values["en"], let russian = values["ru"] else { continue }
                guard russian != english, russian.contains("%") else { continue }
                // Two or more specifiers only. A single `%lld` has no ordering to get wrong, so
                // requiring positional markers there would reject a perfectly ordinary
                // rewording — `Columns: %lld` → `Столбцов: %lld` — for no reason.
                //
                // Counted by `%`, not by scanning the characters `@lld`: those are *letters*,
                // and `%lld` contains three of them, so scanning the set counts one specifier
                // as five and rejects every ordinary rewording in the catalog.
                let specifierCount = russian.filter { $0 == "%" }.count
                guard specifierCount > 1, !russian.contains("$") else { continue }
                suspects.append("\(path): \(key) → \(russian)")
            }
        }
        #expect(suspects.isEmpty, "a reordered translation must use positional specifiers: \(suspects.sorted())")

        // And the value we expect, stated rather than derived — so the assertion above is about
        // the shipped string, not about whatever a heuristic happens to accept.
        var translated: String?
        for (_, table) in try Self.catalogs() {
            if let value = table["%@ at %@"]?["ru"] {
                translated = value
                break
            }
        }
        let russian = try #require(translated, "the event line's Russian translation is missing")
        #expect(russian == "%1$@ в %2$@")
    }
}
