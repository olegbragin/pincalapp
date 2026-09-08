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
    nonisolated public static let themeKey = "appTheme"
    /// The UserDefaults key backing the selected vibe.
    nonisolated public static let vibeKey = "appVibe"

    public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }

    /// The id of the selected vibe (see `PCVibe.all`).
    public var vibeId: String {
        didSet { defaults.set(vibeId, forKey: Self.vibeKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .system
        self.vibeId = defaults.string(forKey: Self.vibeKey) ?? PCVibe.default.id
    }
}
