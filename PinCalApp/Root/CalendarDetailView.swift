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
    /// The session hands out the domain port, not the store, so `SingleCalendarModel`
    /// takes the cache directly. It stops needing one in Stage 9.
    @Environment(\.calendarCache) private var cache
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
            if model?.calendarid != calendarId, let cache {
                model = SingleCalendarModel(
                    calendarid: calendarId,
                    cache: cache,
                    dataProvider: session.dataProvider,
                    eventsSelectionManager: session.eventsSelectionManager,
                    daySelectionManager: session.daySelectionManager,
                    columnCountResolver: session.columnCountResolver
                )
            }
            await model?.fetch(force: true)
        }
    }
}
