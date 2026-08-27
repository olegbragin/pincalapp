//
//  RootNavigation.swift
//  PinCalApp
//

import Observation
import SwiftUI

@Observable
public class RootNavigation {
    public init() {}
    public var selectedCategory: RootSelection? = .calendarList
    public var detailSelection: DetailSelection?
    public var presentedSheet: AppSheet?
    public var path = NavigationPath()

    /// Which column is shown when the split view collapses on iPhone.
    /// Setting `.detail` presents the detail column; the system flips it back
    /// when the user taps Back.
    public var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public var isAtRoot: Bool { path.isEmpty }

    public func open(_ selection: DetailSelection) {
        detailSelection = selection
        preferredCompactColumn = .detail
    }

    public func push(_ route: AppRoute) {
        path.append(route)
    }

    public func present(_ sheet: AppSheet) {
        presentedSheet = sheet
    }
}
