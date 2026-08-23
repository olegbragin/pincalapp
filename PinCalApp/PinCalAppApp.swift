//
//  PinCalAppApp.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 04.05.2026.
//

import SwiftUI

@main
struct PinCalAppApp: App {
    @State private var cache = CalendarCache(manager: CalendarManager())

    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            RootView(cache: cache)
        }
    }
}
