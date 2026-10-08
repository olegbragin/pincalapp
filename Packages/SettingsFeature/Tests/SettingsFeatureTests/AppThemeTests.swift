//
//  AppThemeTests.swift
//  SettingsFeatureTests
//

import SwiftUI
import Testing
import SettingsFeature

@Suite("AppTheme Tests")
struct AppThemeTests {
    @Test("colorScheme maps to the right scheme")
    func colorScheme() {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    @Test("raw value round-trips")
    func rawValueRoundTrip() {
        for theme in AppTheme.allCases {
            #expect(AppTheme(rawValue: theme.rawValue) == theme)
        }
    }

    /// A theme with no label would draw a blank row in the Settings picker, which is the whole
    /// failure this guards — the label is a `switch` over the cases, so the risk is a case being
    /// added and the switch being told to default, which no longer compiles.
    ///
    /// Asserted on *properties* rather than on the English text on purpose: the title resolves
    /// through `String(localized:)`, so its content follows the device's language and a test that
    /// expected "Always light" would fail on a Russian machine for no reason. That the catalog
    /// carries the English source for each phrase is `PCLocalizationCatalogTests`' job.
    @Test("Every theme has a distinct, non-empty label")
    func everyThemeHasALabel() {
        let titles = AppTheme.allCases.map(\.localizedTitle)
        for (theme, title) in zip(AppTheme.allCases, titles) {
            #expect(!title.trimmingCharacters(in: .whitespaces).isEmpty, "\(theme.rawValue) has a blank label")
        }
        #expect(Set(titles).count == titles.count, "two themes share a label: \(titles)")
        #expect(titles.count == AppTheme.allCases.count)
    }
}
