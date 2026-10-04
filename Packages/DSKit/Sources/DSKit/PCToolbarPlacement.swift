//
//  PCToolbarPlacement.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import SwiftUI

public extension ToolbarPlacement {
    /// The navigation-bar toolbar placement: `.navigationBar` on iOS, the window
    /// toolbar on macOS.
    static var pcNavigationBar: ToolbarPlacement {
        #if os(iOS)
            return .navigationBar
        #elseif os(macOS)
            return .windowToolbar
        #else
            return .automatic
        #endif
    }
}

public extension ToolbarItemPlacement {
    /// A leading toolbar item that renders in the platform-appropriate place: the
    /// navigation-bar leading position on iOS, the window toolbar on macOS.
    ///
    /// Added alongside `pcTrailing` for the editor screens' own Back button, which replaces
    /// the system's — see `AddEditEventBatchScreen` for why the system's cannot be used.
    static var pcLeading: ToolbarItemPlacement {
        #if os(iOS)
            return .topBarLeading
        #elseif os(macOS)
            return .automatic
        #else
            return .automatic
        #endif
    }

    /// A trailing toolbar item that renders in the platform-appropriate place:
    /// the navigation-bar trailing position on iOS, the window toolbar on macOS.
    static var pcTrailing: ToolbarItemPlacement {
        #if os(iOS)
            return .topBarTrailing
        #elseif os(macOS)
            return .automatic
        #else
            return .automatic
        #endif
    }

    /// A title toolbar item: the navigation title position on iOS, the principal
    /// (centered) toolbar position on macOS.
    static var pcTitle: ToolbarItemPlacement {
        #if os(iOS)
            return .title
        #elseif os(macOS)
            return .principal
        #else
            return .principal
        #endif
    }
}
