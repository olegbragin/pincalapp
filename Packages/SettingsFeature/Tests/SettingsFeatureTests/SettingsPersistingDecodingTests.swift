//
//  SettingsPersistingDecodingTests.swift
//  SettingsFeatureTests
//

import Foundation
import Testing
import DSKit
@testable import SettingsFeature

/// An in-memory `SettingsPersisting`, so decoding can be tested without a preferences store.
@MainActor
private final class SettingsStoreStub: SettingsPersisting {
    var lastSelectedTheme: String?
    var lastSelectedVibeId: String?
    var lastSelectedCalendarId: Int64?

    init(lastSelectedTheme: String? = nil, lastSelectedVibeId: String? = nil) {
        self.lastSelectedTheme = lastSelectedTheme
        self.lastSelectedVibeId = lastSelectedVibeId
    }
}

/// Covers the decoded view of the settings — `theme` and `vibeId` — and the fallbacks.
///
/// **This is where `unknownStoredThemeFallsBack` lives now, and that is a change of premise rather
/// than a change of expectation.** It used to assert that `SettingsViewModel` decoded a raw string
/// with a fallback; the decoding has moved to `SettingsPersisting+Decoded` because the app root has
/// to read the same values and there must be one definition of what an unrecognised one means. The
/// behaviour is identical — a stale or hand-edited preference still cannot leave the picker with no
/// selection — but the subject is now the port extension rather than the view model, so the test is
/// named for what it checks rather than for the type it used to live on.
///
/// The reason this needs to exist at all is that the store cannot do it: `UserDefaultsSettingsStore`
/// deals in raw values by design, so nothing rejects a bad one until something decodes it.
@MainActor
@Suite("Settings decoding")
struct SettingsPersistingDecodingTests {
    @Test("nothing stored means the system theme")
    func noThemeStored() {
        let store = SettingsStoreStub()

        #expect(store.theme == .system)
    }

    @Test("a stored theme decodes")
    func storedThemeDecodes() {
        let store = SettingsStoreStub(lastSelectedTheme: AppTheme.dark.rawValue)

        #expect(store.theme == .dark)
    }

    /// The one path where the *store* is trusted and the *domain* is not: a stale or hand-edited
    /// preference must not be able to put the picker in a state it cannot render, and
    /// `AppTheme(rawValue:)` returning `nil` is the only thing standing between the two.
    @Test("an unknown stored theme falls back to system")
    func unknownStoredThemeFallsBack() {
        let store = SettingsStoreStub(lastSelectedTheme: "not-a-theme")

        #expect(store.theme == .system)
    }

    /// The fallback is a read, not a repair.
    ///
    /// Rewriting the bad value on the way in would make it indistinguishable from a user who had
    /// genuinely chosen that theme, and it would write to storage during a read — which is the one
    /// thing the store is meant never to do on its own account.
    @Test("an unknown stored theme is left as it is")
    func unknownStoredThemeIsNotRewritten() {
        let store = SettingsStoreStub(lastSelectedTheme: "not-a-theme")

        _ = store.theme

        #expect(store.lastSelectedTheme == "not-a-theme")
    }

    @Test("setting the theme writes the raw value")
    func settingThemeWritesRawValue() {
        let store = SettingsStoreStub()

        store.theme = .light

        #expect(store.lastSelectedTheme == AppTheme.light.rawValue)
    }

    @Test("nothing stored means the default vibe")
    func noVibeStored() {
        let store = SettingsStoreStub()

        #expect(store.vibeId == PCVibe.default.id)
    }

    @Test("a stored vibe id decodes")
    func storedVibeDecodes() {
        let store = SettingsStoreStub(lastSelectedVibeId: PCVibe.default.id)

        #expect(store.vibeId == PCVibe.default.id)
    }

    /// A vibe is validated against `PCVibe.all` rather than merely passed through, because an id
    /// that names no vibe would leave the app applying a vibe that does not exist. There is only one
    /// vibe today, so this is the whole of that check — and it is the test that would notice if a
    /// second vibe arrived and this became wrong in the permissive direction.
    @Test("an unknown stored vibe id falls back to the default")
    func unknownVibeFallsBack() {
        let store = SettingsStoreStub(lastSelectedVibeId: "a-vibe-that-does-not-exist")

        #expect(store.vibeId == PCVibe.default.id)
    }

    @Test("setting the vibe writes the id")
    func settingVibeWritesId() {
        let store = SettingsStoreStub()

        store.vibeId = PCVibe.default.id

        #expect(store.lastSelectedVibeId == PCVibe.default.id)
    }
}
