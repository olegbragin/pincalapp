//
//  SettingsPersisting+Decoded.swift
//  SettingsFeature
//

import Foundation
import DSKit

/// The stored settings as the app's vocabulary, with the fallbacks applied.
///
/// This is the only place in the app where a stored string becomes a domain value, and therefore the
/// only place that can reject one. The store in `CorePersistence` cannot: it deals in raw values by
/// design, so an unrecognised theme survives there until something decodes it.
///
/// It lives on the *protocol* rather than on the view model for two reasons. `RootView` needs the
/// theme and the vibe to render the whole app, and it has the same port the settings screen has — so
/// extending the port gives both one definition instead of two that could disagree. And the fallback
/// is then decided once for every caller: an app that falls back to `.system` in one place and to
/// `.light` in another would show a picker selection the window is not using.
///
/// The stored value is deliberately *not* normalised on the way in. A hand-edited `"not-a-theme"`
/// stays in storage until the user picks something, so the bad value is corrected by the next real
/// choice rather than silently rewritten — but it can never reach the interface, because this is the
/// only path to it.
public extension SettingsPersisting {
    /// The theme the user last chose, or `.system` when nothing is stored or the stored value is not
    /// a theme this build knows.
    var theme: AppTheme {
        get { AppTheme(rawValue: lastSelectedTheme ?? "") ?? .system }
        set { lastSelectedTheme = newValue.rawValue }
    }

    /// The id of the vibe the user last chose, or the default vibe when nothing is stored.
    ///
    /// An unrecognised id falls back too, for the same reason the theme does: a stale preference must
    /// not be able to leave the app rendering a vibe that does not exist.
    var vibeId: String {
        get {
            guard let stored = lastSelectedVibeId else { return PCVibe.default.id }
            return PCVibe.all.contains { $0.id == stored } ? stored : PCVibe.default.id
        }
        set { lastSelectedVibeId = newValue }
    }
}
