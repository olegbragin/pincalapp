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
    case accent
    case eventOption1
    case eventOption2
    case eventOption3
    case eventOption4
    case cardGradientTop
    case cardGradientMid
    case cardGradientBottom
}

/// The semantic text/typography roles used across the app. A vibe provides a
/// concrete font (weight, design, and sizing rules) for each role.
public enum PCFontRole: Hashable, Sendable {
    case dayNumber
    case todayDayNumber
    case weekSymbol
    case headerIcon
    case title
    case badge
    case toolbarIcon
    case metadata
    case footerIcon

    var defaultSpec: PCFontSpec {
        switch self {
        case .dayNumber:
            return PCFontSpec(weight: .regular, size: nil, minSize: 10, maxSize: 20, sizeToCellRatio: 0.49, digitsWidthRatio: 1.3, cellPadding: 2)
        case .todayDayNumber:
            return PCFontSpec(weight: .bold, size: nil, minSize: 10, maxSize: 20, sizeToCellRatio: 0.49, digitsWidthRatio: 1.3, cellPadding: 2)
        case .weekSymbol:
            return PCFontSpec(weight: .regular, size: 13)
        case .headerIcon:
            return PCFontSpec(weight: .semibold, size: 18)
        case .title:
            return PCFontSpec(weight: .semibold, size: 14)
        case .badge:
            return PCFontSpec(weight: .medium, size: 10)
        case .toolbarIcon:
            return PCFontSpec(weight: .semibold, size: 13)
        case .metadata:
            return PCFontSpec(weight: .medium, size: 11)
        case .footerIcon:
            return PCFontSpec(weight: .semibold, size: 12)
        }
    }
}

/// Describes a concrete font: its weight/design and, optionally, the sizing
/// rules used to derive a point size from a layout dimension (e.g. a calendar
/// cell size). When `size` is nil the point size is computed from `cellSize`.
public struct PCFontSpec: Hashable, Sendable {
    public var weight: Font.Weight
    public var design: Font.Design
    /// A fixed point size. When nil, the size is derived from `cellSize`.
    public var size: CGFloat?
    public var minSize: CGFloat
    public var maxSize: CGFloat
    public var sizeToCellRatio: CGFloat
    public var digitsWidthRatio: CGFloat
    public var cellPadding: CGFloat

    public init(
        weight: Font.Weight,
        design: Font.Design = .default,
        size: CGFloat? = nil,
        minSize: CGFloat = 10,
        maxSize: CGFloat = 20,
        sizeToCellRatio: CGFloat = 0.49,
        digitsWidthRatio: CGFloat = 1.3,
        cellPadding: CGFloat = 2
    ) {
        self.weight = weight
        self.design = design
        self.size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.sizeToCellRatio = sizeToCellRatio
        self.digitsWidthRatio = digitsWidthRatio
        self.cellPadding = cellPadding
    }

    /// Resolves the font for a given layout dimension. `cellSize` is ignored
    /// when the spec has a fixed point size.
    public func font(cellSize: CGFloat? = nil) -> Font {
        let pointSize: CGFloat
        if let size {
            pointSize = size
        } else {
            let dimension = cellSize ?? 0
            let fitSize = (dimension - cellPadding * 2) / digitsWidthRatio
            pointSize = min(
                max(dimension * sizeToCellRatio, minSize),
                min(maxSize, fitSize)
            )
        }
        return Font.system(size: pointSize, weight: weight, design: design)
    }
}

/// A color theme. The active vibe is injected via environment and every color
/// in the app resolves through it. The `default` vibe maps each role to the
/// asset-catalog color (which still adapts to the dark/light color scheme).
public struct PCVibe: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    private let colors: [PCColorRole: Color]
    private let fonts: [PCFontRole: PCFontSpec]

    public init(id: String, name: String, colors: [PCColorRole: Color], fonts: [PCFontRole: PCFontSpec] = [:]) {
        self.id = id
        self.name = name
        self.colors = colors
        self.fonts = fonts
    }

    public func color(for role: PCColorRole) -> Color {
        colors[role] ?? .clear
    }

    public func font(for role: PCFontRole, cellSize: CGFloat? = nil) -> Font {
        (fonts[role] ?? role.defaultSpec).font(cellSize: cellSize)
    }

    /// The gradient used to fill the calendar card surface.
    public func cardGradient() -> LinearGradient {
        LinearGradient(
            colors: [
                color(for: .cardGradientTop),
                color(for: .cardGradientMid),
                color(for: .cardGradientBottom),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            .accent: Color(.red),
            .eventOption1: Color("eventColorOption1", bundle: .module),
            .eventOption2: Color("eventColorOption2", bundle: .module),
            .eventOption3: Color("eventColorOption3", bundle: .module),
            .eventOption4: Color("eventColorOption4", bundle: .module),
            .cardGradientTop: Color(red: 0.82, green: 0.83, blue: 0.86),
            .cardGradientMid: Color(red: 0.58, green: 0.60, blue: 0.63),
            .cardGradientBottom: Color(red: 0.42, green: 0.44, blue: 0.47),
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
