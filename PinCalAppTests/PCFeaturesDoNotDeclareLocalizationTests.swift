//
//  PCFeaturesDoNotDeclareLocalizationTests.swift
//  PinCalAppTests
//
//  No feature package holds a localization port, a key enum, or an environment key. Strings
//  resolve through `String(localized:)` and SwiftUI's `LocalizedStringKey`, both of which read the
//  main bundle — so there is nothing for a feature to be handed and nothing for it to map.
//
//  This is the guard for that. It is a source scan because the invariant is about what the
//  packages' text *says*, and there is no call to make and nothing to assert: `Text("Restore")`
//  compiles and behaves correctly whether or not anyone thought about localization.
//
//  What the scan buys is that the next person who writes `enum BatchText: String` gets a failing
//  test instead of a second architecture. The cost is that it is line-based and can be evaded by
//  putting the literal on the line after the initialiser, so it is a regression guard rather than
//  a proof.
//

import Foundation
import Testing

@Suite("Features declare no localization")
struct PCFeaturesDoNotDeclareLocalizationTests {
    /// The repository root, from this file: `…/pincalapp/PinCalAppTests/<this file>` → up two.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func featureSourceFiles() throws -> [URL] {
        let packages = repoRoot.appendingPathComponent("Packages")
        guard FileManager.default.fileExists(atPath: packages.path) else {
            throw PackagesMissing(path: packages.path)
        }
        return try FileManager.default
            .subpathsOfDirectory(atPath: packages.path)
            .filter { $0.hasSuffix(".swift") }
            .filter { $0.contains("/Sources/") && !$0.contains("/.build/") }
            .map { packages.appendingPathComponent($0) }
            .sorted { $0.path < $1.path }
    }

    private struct PackagesMissing: Error, CustomStringConvertible {
        let path: String
        init(path: String) {
            self.path = path
        }

        var description: String {
            "no Packages directory at \(path) — this test would otherwise pass vacuously"
        }
    }

    /// Comments are blanked first: the rule is about code, and the comments explaining it should be
    /// able to name the things they keep out.
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
            if let slash = line.range(of: "//") {
                line = line[..<slash.lowerBound]
            }
            return String(line)
        }
    }

    private static func hits(on needles: [String]) throws -> [String] {
        var found: [String] = []
        let packages = repoRoot.appendingPathComponent("Packages").path + "/"
        for file in try featureSourceFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: packages, with: "")
            for (index, line) in codeOnly(contents).enumerated()
                where needles.contains(where: { line.contains($0) })
            {
                found.append("\(relative):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return found
    }

    @Test("No feature declares a localization port or a key enum")
    func noLocalizationDeclarations() throws {
        let needles = [
            // The ports and key types that used to exist, by name. Unambiguous, and the point is
            // that they are gone — a test that named only the shape would let a renamed version
            // through.
            "protocol DSKitLocalizing",
            "protocol CalendarListLocalizing",
            "protocol SettingsLocalizing",
            "protocol SingleCalendarLocalizing",
            "protocol PCLocalization",
            "DSKitText",
            "PCStringKey",
            "StringKey",
            "Localizing",
            "EnglishLocalization",
            // `.xcstrings` is *not* in this list: a package owning a catalog is the design now.
            "NSLocalizedString",
            "import PinCalLocalization",
            // The shape every one of those key enums had. A heuristic, and deliberately tight:
            // `String, CaseIterable` on its own also matches `AppTheme` and `DisplayMode`, which
            // are ordinary domain enums and have every right to be. `Sendable` was on the line
            // too, and a *domain* enum wanting it is rarer than a fourth architecture appearing.
            ": String, CaseIterable, Sendable",
        ]
        let found = try Self.hits(on: needles)
        #expect(found.isEmpty, "a feature package has taken on localization itself:\n\(found.joined(separator: "\n"))")
    }

    @Test("No feature reads a localization environment key")
    func noLocalizationEnvironmentKeys() throws {
        // The `@Entry` needles end at the `:` so that `@Entry var settingsPersisting` — which is a
        // settings *port*, and is supposed to exist — does not match `settings`.
        let needles = [
            "@Environment(\\.calendarList)",
            "@Environment(\\.singleCalendar)",
            "@Environment(\\.settings)",
            "@Environment(\\.dskit)",
            "@Environment(\\.pclocalization)",
            "@Entry var calendarList:",
            "@Entry var singleCalendar:",
            "@Entry var settings:",
            "@Entry var dskit:",
            "@Entry var pclocalization:",
        ]
        let found = try Self.hits(on: needles)
        #expect(found.isEmpty, "a feature reads an injected localization service:\n\(found.joined(separator: "\n"))")
    }

    /// The app target is allowed — and expected — to own a catalog, since the main bundle is
    /// what `Text("…")` resolves in.
    ///
    /// A catalog outside the app target is now the *design* rather than a violation: each package
    /// owns one so that Xcode tracks its keys against the target that uses them, which is what
    /// stops the catalog editor reporting every package string as unreferenced. What must hold is
    /// that a package catalog is actually compiled — which is `PCLocalizationCatalogTests`' job,
    /// and which fails loudly if a `Package.swift` loses its `resources:` line.
    @Test("The app target owns a catalog")
    func appCatalogExists() {
        let inApp = Self.repoRoot.appendingPathComponent("PinCalApp/Localizable.xcstrings")
        #expect(
            FileManager.default.fileExists(atPath: inApp.path),
            "the app bundle needs a Localizable.xcstrings, or a localized Text resolves nothing"
        )
    }
}
