//
//  CalendarDetailView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 22.10.2025.
//

import SwiftUI
import CoreDomain
import DSKit
import SingleCalendarFeature

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
    @Environment(PCAppSession.self) private var session
    @Environment(\.pcErrorRecorder) private var errorRecorder
    @State private var model: SingleCalendarModel?

    var body: some View {
        Group {
            if let model {
                SingleCalendarView(
                    viewModel: model
                )
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
            // A failed *re*fetch no longer empties the store's batches or leaves this
            // column half-updated — the two damaging cases, and both are fixed.
            //
            // The initial load is **not** fixed and this comment previously claimed otherwise:
            // `state` starts as `.empty`, which draws `EmptyView`, so a first fetch that throws
            // still shows a blank column. It just no longer *replaces* good content with
            // nothing. Giving `.empty` a failure case, and telling the user, is still to do.
            try? await model?.fetch(force: true)
        }
        /// Records a batch write that did not land.
        ///
        /// Observed here rather than taken as an `onSaveFailed` callback on `SingleCalendarView`,
        /// which is where it used to come from. That view does not own `failedSave` — the store
        /// does — so the callback was the view relaying an event it had merely observed, and the
        /// app target already holds the very store it was being told about. One owner now: this
        /// view, reading the same observable state the retry toast reads.
        ///
        /// Fires on the `nil -> failure` edge only, because `onChange` gives the new value rather
        /// than the transition. Re-recording the same failure would otherwise write a second row.
        .onChange(of: session.eventSelection(for: calendarId).failedSave) { _, failure in
            guard let failure else { return }
            errorRecorder.record(failure, operation: "eventBatch.save")
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
