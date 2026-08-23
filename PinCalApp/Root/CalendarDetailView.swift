//
//  CalendarDetailView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 22.10.2025.
//

import SwiftUI

struct CalendarDetailView: View {
    let calendarId: Int64
    let cache: CalendarCache
    @State private var model: SingleCalendarModel

    init(calendarId: Int64, cache: CalendarCache) {
        self.calendarId = calendarId
        self.cache = cache
        self._model = State(initialValue: SingleCalendarModel(calendarid: calendarId, cache: cache))
    }

    var body: some View {
        SingleCalendarView(viewModel: model)
            .id(calendarId)
            .accessibilityIdentifier("calendar-detail-\(calendarId)")
            .task(id: calendarId) {
                if model.calendarid != calendarId {
                    model = SingleCalendarModel(calendarid: calendarId, cache: cache)
                }
                await model.fetch(force: true)
            }
    }
}
