//
//  SettingsViewModel.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 08.09.2026.
//

import Foundation
import Observation
import DSKit

@MainActor
@Observable
public final class SettingsViewModel {
    /// The UserDefaults key backing the theme preference.
    public nonisolated static let themeKey = "appTheme"
    /// The UserDefaults key backing the selected vibe.
    public nonisolated static let vibeKey = "appVibe"

    public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }

    /// The id of the selected vibe (see `PCVibe.all`).
    public var vibeId: String {
        didSet { defaults.set(vibeId, forKey: Self.vibeKey) }
    }

    private let defaults: UserDefaults

    /// `defaults` has no default value on purpose.
    ///
    /// It used to default to `.standard`, which made the process-wide store the path of least
    /// resistance: a caller that forgot to pass one got a view model that silently read and wrote
    /// the user's real preferences. Every test already passed its own UUID-named suite, so nothing
    /// was actually broken — but the hazard was one omitted argument away, and the tests were
    /// passing only because they happened to be the careful ones.
    ///
    /// Requiring it makes `SettingsView` state that the app really does use `.standard`, which is
    /// the one place that should know it.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .system
        self.vibeId = defaults.string(forKey: Self.vibeKey) ?? PCVibe.default.id
    }
}
