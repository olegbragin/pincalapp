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

    public var id: String { rawValue }

    /// The `ColorScheme` to force, or `nil` to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }
}
