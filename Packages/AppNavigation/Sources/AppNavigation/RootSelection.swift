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

/// Lightweight event data for navigation routing.
public struct EventEditorSource: Hashable {
    public var id: Int64
    public var name: String
    public var date: Date
    public var color: String
    public var timestamp: UUID?

    public init(id: Int64, name: String, date: Date, color: String, timestamp: UUID? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.color = color
        self.timestamp = timestamp
    }
}

/// Single global enum for all possible navigation routes in the app.
public enum AppRoute: Hashable {
    // Sidebar category selection
    case sidebar(SidebarCategory)
    
    // Split-view detail column replacements (open)
    case calendar(Int64, toRoot: Bool)
    
    // Navigation stack pushes
    case dayBatches(Date)
    case batchEditor(BatchEditorSource)
    case eventEditor(EventEditorSource)
    
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
