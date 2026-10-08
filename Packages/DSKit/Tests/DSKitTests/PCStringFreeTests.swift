//
//  PCStringFreeTests.swift
//  DSKitTests
//
//  `DSKit` does not localize. Every string it draws — a badge, a navigation title, an option name,
//  a field placeholder — arrives as a property from whichever feature put the component on screen.
//
//  That is not a style preference, and it is not the kind of rule a compiler enforces on its own:
//  nothing stops the next person writing `Text("Restore")` in a shared view, and SwiftUI would
//  quietly treat that literal as a `LocalizedStringKey` and look it up in *this package's* bundle,
//  which has no catalog to look it up in. The result is a word that never translates and reads as
//  correct in whatever language the developer happens to run.
//
//  So these two tests read the sources. A behavioural test cannot check this: there is no call to
//  make and nothing to assert, because the invariant is about what the package's text *says*.
//  The dependency half of it — that `DSKit` cannot even name `PCStringKey` — is already
//  compile-time, since `Package.swift` gives this target no dependency on `PinCalLocalization`.
//

import Foundation
import Testing
@testable import DSKit

@Suite("DSKit is string-free")
struct PCStringFreeTests {
    /// This package's `Sources/DSKit`, located from this file so the test needs no configuration.
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath) // …/Packages/DSKit/Tests/DSKitTests/<this file>
            .deletingLastPathComponent() // …/Packages/DSKit/Tests/DSKitTests
            .deletingLastPathComponent() // …/Packages/DSKit/Tests
            .deletingLastPathComponent() // …/Packages/DSKit
            .appendingPathComponent("Sources/DSKit")
    }

    private static func sourceFiles() throws -> [URL] {
        let root = sourcesRoot
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw SourceRootMissing(path: root.path)
        }
        return try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .map { root.appendingPathComponent($0) }
            .sorted { $0.path < $1.path }
    }

    /// Carries the missing-root path out so a failure says *where* it looked, rather than reading
    /// as "no files matched, therefore clean" — which is the failure mode that lets a source scan
    /// pass vacuously.
    private struct SourceRootMissing: Error, CustomStringConvertible {
        let path: String
        var description: String {
            "no DSKit sources at \(path) — this test would otherwise pass without checking anything"
        }
    }

    /// Every line mentioning any of `needles`, as `file:line  text`, so a failure names a place a
    /// reader can jump to rather than just counting offenders.
    ///
    /// Comments are blanked first. The invariant is about *code*, and the comments explaining it
    /// are supposed to name the things they are keeping out — a scan that flagged those would make
    /// the rule impossible to document, and the natural response would be to delete the
    /// explanation rather than fix the code.
    private static func mentions(of needles: [String]) throws -> [String] {
        var hits: [String] = []
        for file in try sourceFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: Self.sourcesRoot.path + "/", with: "")
            for (index, line) in codeOnly(contents).enumerated() {
                guard needles.contains(where: { line.contains($0) }) else { continue }
                hits.append("\(relative):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return hits
    }

    /// `contents` with comments replaced by empty space, line for line, so reported line numbers
    /// still point at the right place.
    ///
    /// A line-comment strip is exact for `//`. Block comments are handled with a carried flag
    /// rather than a proper lexer: a `/*` inside a string literal would confuse it, which is a
    /// false *negative* on a violation — the safe direction to be wrong in for a guard.
    private static func codeOnly(_ contents: String) -> [String] {
        var inBlockComment = false
        return contents.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            var line = Substring(raw)
            if inBlockComment {
                guard let end = line.range(of: "*/") else { return "" }
                line = line[end.upperBound...]
                inBlockComment = false
            }
            while let start = line.range(of: "/*") {
                guard let end = line.range(of: "*/", range: start.upperBound..<line.endIndex) else {
                    line = line[..<start.lowerBound]
                    inBlockComment = true
                    break
                }
                line = line[..<start.lowerBound] + line[end.upperBound...]
            }
            // Line comment last: `//` inside a string literal would cut a line short, which is
            // again a false negative rather than a false positive.
            if let slash = line.range(of: "//") {
                line = line[..<slash.lowerBound]
            }
            return String(line)
        }
    }

    @Test("No source names a localization port, a catalog, or the environment key")
    func noLocalizationIdentifiers() throws {
        let needles = [
            "DSKitLocalizing",
            "DSKitText",
            "EnglishDSKitLocalization",
            "\\.dskit",
            "PCLocalization",
            "PCStringKey",
            "PinCalLocalization",
            ".xcstrings",
            "localizedString",
            "NSLocalizedString",
        ]
        let hits = try Self.mentions(of: needles)
        #expect(hits.isEmpty, "DSKit must not reference localization:\n\(hits.joined(separator: "\n"))")
    }

    /// The literal that actually breaks it: SwiftUI reads `Text("…")` as a `LocalizedStringKey`
    /// and searches this package's bundle for it, finding nothing and showing the English source
    /// forever.
    ///
    /// The test is "does a literal sit in *first-argument* position of a user-facing initialiser".
    /// That placement is the whole question: `PCTextField(title: "…", …)` takes its label behind a
    /// label and is fine, while `Label("Restore", systemImage:)` is not — the string is the text a
    /// user reads. Accessibility *identifiers* and SF Symbol names are also first-argument
    /// literals, and they are deliberately not localized, so `accessibilityIdentifier` and
    /// `Image(systemName:` are simply not in the list below.
    ///
    /// Line-based, so a literal wrapped onto the line after `Text(` would slip past. That is a
    /// known limit of a text scan and the reason this is a regression guard rather than a proof.
    @Test("No source hands a string literal to a user-facing initialiser")
    func noHardcodedUserFacingStrings() throws {
        let initialisers = [
            "Text(\"", "TextField(\"", "Label(\"", "Section(\"", "Button(\"",
            "Picker(\"", "ContentUnavailableView(\"", "navigationTitle(\"",
            "accessibilityLabel(\"", "accessibilityHint(\"",
        ]

        var hits: [String] = []
        for file in try Self.sourceFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: Self.sourcesRoot.path + "/", with: "")
            for (index, line) in Self.codeOnly(contents).enumerated()
                where initialisers.contains(where: { line.contains($0) })
            {
                hits.append("\(relative):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(hits.isEmpty, "DSKit must not choose its own words:\n\(hits.joined(separator: "\n"))")
    }

    /// The regression this refactor fixed, pinned so it cannot come back unnoticed: the calendar
    /// card had a hardcoded `TextField("Calendar name")` placeholder that survived an earlier pass
    /// that only looked for the localization port.
    @Test("The calendar card's rename field has no literal placeholder")
    func cardPlaceholderIsSupplied() throws {
        let file = Self.sourcesRoot
            .appendingPathComponent("CalendarCard/PCCalendarCardView.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        let line = try #require(
            contents.split(separator: "\n").first { $0.contains("TextField(") },
            "the card's rename field is gone — check this test still describes the code"
        )
        #expect(!line.contains("\""), "placeholder came back as a literal: \(line)")
    }
}
