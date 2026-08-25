//
//  RootNavigation.swift
//  PinCalApp
//

import Observation
import SwiftUI

@Observable
class RootNavigation {
    var selectedCategory: RootSelection? = .calendarList
    var detailSelection: DetailSelection?
    var presentedSheet: AppSheet?
    var path = NavigationPath()

    /// Which column is shown when the split view collapses on iPhone.
    /// Setting `.detail` presents the detail column; the system flips it back
    /// when the user taps Back.
    var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var isAtRoot: Bool { path.isEmpty }

    func open(_ selection: DetailSelection) {
        detailSelection = selection
        preferredCompactColumn = .detail
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func present(_ sheet: AppSheet) {
        presentedSheet = sheet
    }
}
