//
//  ContentView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 22.10.2025.
//

import SwiftUI

struct RootDetailView: View {
    @Binding var selector: RootSelectionCoordinator
    
    var body: some View {
        NavigationStack {
            switch selector.selectedItem {
            case .calendar(let id):
                SingleCalendarView(
                    viewModel: .init(calendarid: id)
                )
            default:
                Text("Select a calendar from the sidebar")
            }
        }
    }
}
