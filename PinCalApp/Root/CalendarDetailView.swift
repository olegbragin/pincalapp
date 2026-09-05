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
    let cache: CalendarCache
    let eventsSelectionManager: PCEventsSelectionManager
    let daySelectionManager: PCCalendarDaySelectionManager
    @State private var model: SingleCalendarModel

    init(
        calendarId: Int64,
        cache: CalendarCache,
        eventsSelectionManager: PCEventsSelectionManager,
        daySelectionManager: PCCalendarDaySelectionManager
    ) {
        self.calendarId = calendarId
        self.cache = cache
        self.eventsSelectionManager = eventsSelectionManager
        self.daySelectionManager = daySelectionManager
        self._model = State(initialValue: SingleCalendarModel(
            calendarid: calendarId,
            cache: cache,
            eventsSelectionManager: eventsSelectionManager,
            daySelectionManager: daySelectionManager
        ))
    }

    var body: some View {
        SingleCalendarView(viewModel: model)
            .id(calendarId)
            .accessibilityIdentifier("calendar-detail-\(calendarId)")
            .task(id: calendarId) {
                if model.calendarid != calendarId {
                    model = SingleCalendarModel(
                        calendarid: calendarId,
                        cache: cache,
                        eventsSelectionManager: eventsSelectionManager,
                        daySelectionManager: daySelectionManager
                    )
                }
                await model.fetch(force: true)
            }
    }
}
