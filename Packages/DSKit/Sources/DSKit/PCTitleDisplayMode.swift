//
//  PCTitleDisplayMode.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import SwiftUI

/// Cross-platform navigation bar title display mode. The platform APIs differ
/// (`navigationBarTitleDisplayMode` on iOS, `toolbarTitleDisplayMode` on macOS),
/// so this maps a single value onto the right one (OCP: adding a platform is a
/// new branch, not a change to call sites).
public enum PCTitleDisplayMode {
    case automatic
    case inline
}

public extension View {
    func pcNavigationBarTitleDisplayMode(_ mode: PCTitleDisplayMode = .inline) -> some View {
        #if os(iOS)
        switch mode {
        case .automatic: return navigationBarTitleDisplayMode(.automatic)
        case .inline: return navigationBarTitleDisplayMode(.inline)
        }
        #elseif os(macOS)
        switch mode {
        case .automatic: return toolbarTitleDisplayMode(.automatic)
        case .inline: return toolbarTitleDisplayMode(.inline)
        }
        #else
        return self
        #endif
    }
}
