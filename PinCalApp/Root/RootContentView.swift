//
//  RooContentView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 20.02.2026.
//

import SwiftUI

struct RootContentView: View {
    @Binding var selector: RootSelectionCoordinator
    
    var body: some View {
        NavigationStack {
            switch selector.selectedCategory {
            case .calendarList:
                CalendarListView(selector: $selector)
            default:
                EmptyView()
            }
        }
    }
}
