//
//  CalendarDetailView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 22.10.2025.
//

import SwiftUI
import CoreDomain
import SingleCalendarFeature
import CorePersistence
import DSKit

struct CalendarDetailView: View {
    let calendarId: Int64
    @Environment(PCCalendarSession.self) private var session
    @State private var model: SingleCalendarModel?

    var body: some View {
        Group {
            if let model {
                SingleCalendarView(viewModel: model)
                    .id(calendarId)
                    .accessibilityIdentifier("calendar-detail-\(calendarId)")
            } else {
                ProgressView()
            }
        }
        .task(id: calendarId) {
            if model?.calendarid != calendarId {
                model = SingleCalendarModel(
                    calendarid: calendarId,
                    cache: session.cache,
                    dataProvider: session.dataProvider,
                    eventsSelectionManager: session.eventsSelectionManager,
                    daySelectionManager: session.daySelectionManager
                )
            }
            await model?.fetch(force: true)
        }
    }
}
