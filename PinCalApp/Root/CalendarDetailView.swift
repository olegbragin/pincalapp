//
//  CalendarDetailView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 22.10.2025.
//

import SwiftUI
import CoreDomain
import SingleCalendarFeature
import DSKit

/// One calendar's detail column.
///
/// Owns the hand-off between "which calendar" and "what is on screen": the model is per calendar
/// and is reached through the session rather than stored globally.
///
/// The store is not injected here: `PinCalAppApp` injects the current calendar's app-wide,
/// because a `navigationDestination`'s content does not inherit an environment applied below the
/// `NavigationStack`. This view asks the session for *its* store rather than reading it from the
/// environment, so it cannot be handed the wrong calendar's.
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
                    managing: session.managing,
                    persistence: session.persistence,
                    store: session.eventSelection(for: calendarId),
                    dataProvider: session.dataProvider,
                    columnCountResolver: session.columnCountResolver
                )
            }
            await model?.fetch(force: true)
        }
        .onDisappear {
            // Leaving the calendar ends any multi-select session, on both platforms: on iPhone
            // this is Back, and on iPad the detail column is replaced when another calendar is
            // selected.
            //
            // It is here *and* in `RootNavigation.switchCalendar` on purpose. This one covers
            // the ordinary leave, but it depends on this view being torn down — and on iPad the
            // detail column sometimes never loads at all, so there may be no view to tear down
            // while a session is live. The switch hook does not depend on that.
            session.endSession(for: calendarId)
        }
    }
}