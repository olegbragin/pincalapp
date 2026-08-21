//
//  RootNavigation.swift
//  PinCalApp
//

import Observation
import SwiftUI

@Observable
class RootNavigation {
    var selectedCategory: RootSelection? = .calendarList
    var selectedRoute: AppRoute?
    var path = NavigationPath()

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        selectedRoute = nil
        path = NavigationPath()
    }
}
