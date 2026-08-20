//
//  RootView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 07.02.2026.
//

import SwiftUI

struct RootView: View {
    @State var navigation = RootNavigation()

    var body: some View {
        NavigationSplitView {
            RootContentView(navigation: $navigation)
        } detail: {
            NavigationStack {
                switch navigation.selectedItem {
                case .calendar(let id):
                    CalendarDetailView(calendarId: id)
                default:
                    Text("Select a calendar from the sidebar")
                }
            }
            .background(.colorBackgroundMain)
        }
        .padding(0)
    }
}
