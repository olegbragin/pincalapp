//
//  PCSystemColor.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Central place for system colors that differ between platforms, so views never
/// reference `UIColor`/`NSColor` directly (DIP). Adding a new platform is just a
/// new branch here (OCP).
public enum PCSystemColor {
    /// The standard secondary system background (grouped list background).
    public static var secondarySystemBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }

    /// The standard grouped system background.
    public static var systemGroupedBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }
}
