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
                CalendarDetailView(calendarId: id)
            default:
                Text("Select a calendar from the sidebar")
            }
        }
    }
}

struct CalendarDetailView: View {
    let calendarId: Int64
    @State private var model: SingleCalendarModel

    init(calendarId: Int64) {
        self.calendarId = calendarId
        self._model = State(initialValue: SingleCalendarModel(calendarid: calendarId))
    }

    var body: some View {
        SingleCalendarView(viewModel: model)
            .id(calendarId)
    }
}
