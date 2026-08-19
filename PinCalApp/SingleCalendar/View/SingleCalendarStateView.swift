//
//  SingleCalendarStateView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct SingleCalendarStateView: View {
    var state: SingleCalendarModel.State
    var calendarContent: () -> AnyView

    var body: some View {
        switch state {
        case .empty:
            EmptyView()
        case .loading:
            PCProgressView(label: "Loading")
        case .content:
            calendarContent()
        }
    }
}

#Preview("Loading") {
    SingleCalendarStateView(state: .loading) {
        AnyView(Text("Content"))
    }
}

#Preview("Empty") {
    SingleCalendarStateView(state: .empty) {
        AnyView(Text("Content"))
    }
}
