//
//  PCVibe.swift
//  DSKit
//
//  Created by Oleg Bragin on 08.09.2026.
//

import SwiftUI

/// The named color roles used across the app. A vibe provides a concrete color
/// for each role.
public enum PCColorRole: Hashable, Sendable {
    case background
    case backgroundMain
    case backgroundDisabled
    case foreground
    case foregroundDisabled
    case foregroundEvent
    case foregroundOnEventCard
    case eventOption1
    case eventOption2
    case eventOption3
    case eventOption4
}

/// A color theme. The active vibe is injected via environment and every color
/// in the app resolves through it. The `default` vibe maps each role to the
/// asset-catalog color (which still adapts to the dark/light color scheme).
public struct PCVibe: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    private let colors: [PCColorRole: Color]

    public init(id: String, name: String, colors: [PCColorRole: Color]) {
        self.id = id
        self.name = name
        self.colors = colors
    }

    public func color(for role: PCColorRole) -> Color {
        colors[role] ?? .clear
    }

    public func eventColor(for option: PCColorOption) -> Color {
        color(for: option.colorRole)
    }

    public func eventColor(named colorName: String) -> Color {
        guard let option = PCColorOption(colorName) else { return .clear }
        return eventColor(for: option)
    }

    public static let `default` = PCVibe(
        id: "default",
        name: "Default",
        colors: [
            .background: Color("colorBackground", bundle: .module),
            .backgroundMain: Color("colorBackgroundMain", bundle: .module),
            .backgroundDisabled: Color("colorBackgroundDisabled", bundle: .module),
            .foreground: Color("colorForeground", bundle: .module),
            .foregroundDisabled: Color("colorForegroundDisabled", bundle: .module),
            .foregroundEvent: Color("colorForegroundEvent", bundle: .module),
            .foregroundOnEventCard: Color("colorForegroundOnEventCard", bundle: .module),
            .eventOption1: Color("eventColorOption1", bundle: .module),
            .eventOption2: Color("eventColorOption2", bundle: .module),
            .eventOption3: Color("eventColorOption3", bundle: .module),
            .eventOption4: Color("eventColorOption4", bundle: .module),
        ]
    )

    /// The available vibes. Custom vibes (from the future theme editor) are
    /// added here.
    public static let all: [PCVibe] = [.default]
}

public extension PCColorOption {
    var colorRole: PCColorRole {
        switch self {
        case .option1: return .eventOption1
        case .option2: return .eventOption2
        case .option3: return .eventOption3
        case .option4: return .eventOption4
        }
    }
}

private struct PCVibeKey: EnvironmentKey {
    static let defaultValue: PCVibe = .default
}

public extension EnvironmentValues {
    var pcVibe: PCVibe {
        get { self[PCVibeKey.self] }
        set { self[PCVibeKey.self] = newValue }
    }
}

public extension View {
    /// Sets the active vibe for the view subtree.
    func pcVibe(_ vibe: PCVibe) -> some View {
        environment(\.pcVibe, vibe)
    }
}
