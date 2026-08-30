//
 //  RootNavigation.swift
 //  PinCalApp
 //

import Observation
import SwiftUI

@Observable
public class RootNavigation {
    public init() {}
    public var selectedSidebarCategory: SidebarCategory? = .calendarList
    public var path = NavigationPath()

    /// Which column is shown when the split view collapses on iPhone.
    /// Setting `.detail` presents the detail column; the system flips it back
    /// when the user taps Back.
    public var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public var isAtRoot: Bool { path.isEmpty }

    /// Current detail column selection (for split-view "open" navigation)
    public private(set) var detailCalendarID: Int64?
    
    /// Currently presented sheet
    public private(set) var presentedSheet: AppRoute?

    /// Unified navigation — single entry point for all routes.
    /// The route itself (via AppRoute.navigationStyle) defines how to navigate.
    public func goTo(_ route: AppRoute) {
        switch route {
        // MARK: - Sidebar category selection (changes content column)
        case .sidebar(let category):
            selectedSidebarCategory = category
            if category == .archived {
                detailCalendarID = nil
            }
            
        // MARK: - Open (split-view detail column replacement)
        case .calendar(let id):
            detailCalendarID = id
            preferredCompactColumn = .detail
            presentedSheet = nil
            
        // MARK: - Push (navigation stack)
        case .dayBatches:
            path.append(route)
        case .batchEditor:
            path.append(route)
            
        // MARK: - Present (sheet)
        case .addCalendar:
            presentedSheet = route
        }
    }
    
    /// Dismiss presented sheet
    public func dismissSheet() {
        presentedSheet = nil
    }
    
    /// Clear navigation stack (pop to root)
    public func popToRoot() {
        path = NavigationPath()
    }
}
