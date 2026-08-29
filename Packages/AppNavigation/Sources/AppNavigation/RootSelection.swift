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
}

/// What the batch editor screen should be opened with.
public enum BatchEditorSource: Hashable {
    case newDay(Date)
    case existingBatch(Int64)
}

/// Single global enum for all possible navigation routes in the app.
public enum AppRoute: Hashable {
    // Sidebar category selection
    case sidebar(SidebarCategory)
    
    // Split-view detail column replacements (open)
    case calendar(Int64)
    
    // Navigation stack pushes
    case dayBatches(Date)
    case batchEditor(BatchEditorSource)
    
    // Sheets
    case addCalendar
    
    var navigationStyle: NavigationStyle {
        switch self {
        case .sidebar:
            return .open  // Changes split-view content column
        case .calendar:
            return .open
        case .dayBatches, .batchEditor:
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
