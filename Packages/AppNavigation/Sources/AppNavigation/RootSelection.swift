//
 //  RootSelection.swift
 //  USkateAppV2
 //
 //  Created by Oleg Bragin on 19.02.2026.
 //

import Foundation
import Observation
import SwiftUI

/// Sidebar categories — now part of AppRoute for centralized navigation handling
public enum SidebarCategory: Equatable, Hashable {
    case calendarList
    case archived
    case settings
}

/// Single global enum for all possible navigation routes in the app.
///
/// The three push cases carry no payload. They used to: `dayBatches(Date)`,
/// `batchEditor(BatchEditorSource)` and `eventEditor(EventEditorSource)` shipped the day,
/// the batch and the event across in the route. That data is in the batch-assembly store
/// now, and a payload was a *snapshot* of it — push the editor, edit the batch, and the
/// destination already held a stale copy of what the store said. Two copies of "which
/// batch am I editing" is the second source of truth this package exists to avoid.
///
/// So a route says only *where*, and the destination reads *what* from the store. A
/// screen cannot be handed a different event than the store says is open, because there
/// is no longer a way to hand it one.
public enum AppRoute: Hashable {
    // Sidebar category selection
    case sidebar(SidebarCategory)
    
    // Split-view detail column replacements (open)
    case calendar(Int64, toRoot: Bool)
    
    // Navigation stack pushes
    case dayBatches
    case batchEditor
    case eventEditor
    
    // Sheets
    case addCalendar
    
    var navigationStyle: NavigationStyle {
        switch self {
        case .sidebar:
            return .open  // Changes split-view content column
        case .calendar:
            return .open
        case .dayBatches, .batchEditor, .eventEditor:
            return .push
        case .addCalendar:
            return .present
        }
    }
}

/// Navigation style for a route
public enum NavigationStyle {
    case push
    case open
    case present
}
