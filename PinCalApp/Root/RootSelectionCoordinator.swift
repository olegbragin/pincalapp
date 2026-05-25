//
//  RootNavigation.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 22.02.2026.
//

import Observation

@Observable
class RootSelectionCoordinator {
    var selectedCategory: RootSelection? = .calendarList
    var selectedItem: RootSelection?

//    func selectCategory(_ category: String) {
//        selectedMenuNode = .category(category)
//    }
//
//    func selectSubitem(category: String, subitem: String) {
//        selectedMenuNode = .subitem(category, subitem)
//    }
//
//    func showDetail(subitem: String, details: String) {
//        selectedMenuNode = .detail(subitem, details)
//    }
//
//    var currentMenuNode: String? {
//        guard case .category(let cat) = selectedRoute else { return nil }
//        return cat
//    }
//
//    var currentSubitem: String? {
//        guard case .subitem(_, let sub) = selectedRoute else { return nil }
//        return sub
//    }
}
