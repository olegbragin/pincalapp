//
//  AppTheme.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 08.09.2026.
//

import SwiftUI

/// The app's color-scheme preference.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String {
        rawValue
    }

    /// The `ColorScheme` to force, or `nil` to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public extension AppTheme {
    /// The theme's name as the user reads it.
    ///
    /// On the enum rather than in `SettingsView` because the label belongs to the theme, and
    /// because a `switch` is what makes adding a fourth case a compile error here instead of a
    /// blank row in the picker.
    ///
    /// `String(localized:)` takes a *literal*, which is the point: Xcode extracts it into
    /// `pcLocalisation.xcstrings` on build, so the label can be translated without anyone editing
    /// the catalog by hand. `AppTheme` deliberately holds no key and no port — it names nothing
    /// until the view asks it to.
    var localizedTitle: String {
        switch self {
        case .system: return String(localized: .system)
        case .light: return String(localized: .alwaysLight)
        case .dark: return String(localized: .alwaysDark)
        }
    }
}
