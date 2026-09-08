//
//  SettingsViewModel.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 08.09.2026.
//

import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    /// The UserDefaults key backing the theme preference.
    nonisolated public static let themeKey = "appTheme"

    public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .system
    }
}
