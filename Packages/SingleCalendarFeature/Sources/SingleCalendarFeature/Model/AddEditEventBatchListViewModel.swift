//
//  AddEditEventBatchListViewModel.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 08.07.2026.
//

import Foundation
import Observation
import CoreDomain
import DSKit

/// The list of batches on one day.
///
/// The only view model that still stores anything, and what it stores is view-scoped:
/// which batch is staged for deletion. That is not part of the batch domain and the
/// reducer has no opinion about it.
///
/// `eventBatches` is **computed**. It used to be a stored copy re-primed by hand in
/// `onAppear` and again in `onChange(of: eventBatchesToDelete)`, precisely because a
/// computed version had been found not to re-render after a deletion. That work-around
/// existed only to compensate for holding a duplicate of state the reducer owns. With one
/// copy there is nothing to re-prime, and a deletion is already reflected in the next
/// render. §12.5 pins this so it cannot regress.
@MainActor
@Observable
public final class AddEditEventBatchListViewModel {
    private let store: PCEventSelectionManager

    /// View-scoped only — permitted by the "no domain state in a view model" rule.
    var pendingDeletion: [CalendarEventBatch] = []

    init(store: PCEventSelectionManager) {
        self.store = store
    }

    // MARK: - Projections

    /// The batches on the selected day, each narrowed to that day.
    ///
    /// Two filters, and the second is the one this screen was missing. `dayBatches` already
    /// answers "which batches touch this day"; it handed back the whole batch, so a batch
    /// covering four days listed under the first of them showed three events belonging to
    /// days the user was not on. `on(_:using:)` keeps the row's identity — `mergeKey`,
    /// `persistedID`, `pendingID` — so opening, deleting and merging all still address the
    /// batch it was drawn from, and only the *drawn* content is the day's.
    var eventBatches: [CalendarEventBatch] {
        let day = store.state.day
        let batches = store.state.dayBatches
        guard let day else { return batches }
        return batches.map { $0.on(day, using: store.state.dataProvider) }
    }

    var selectedDay: Date? {
        store.state.day
    }

    /// How a card's event row is stamped: the event's date *and* time, e.g.
    /// "Jul 15, 2026 at 3:45 PM".
    ///
    /// The format itself belongs to `CalendarEvent.dateTimeText`, which the batch editor's
    /// event list also reads — the two screens list the same event, and two copies of the
    /// format is how they start disagreeing about it.
    func dateTimeText(for event: CalendarEvent) -> String {
        event.dateTimeText
    }

    // MARK: - Commands

    /// Stages a batch for deletion. It stays in the list until `confirmDelete`.
    ///
    /// There used to be a `cancel` alongside this, and a test for it. Nothing could reach it:
    /// the list drives `confirmDelete` straight off `onChange(of: pendingDeletion)`, so a
    /// staged deletion was confirmed on the very next frame and there was never a moment a
    /// user could change their mind. It was a projection kept alive only by its own test —
    /// which is the `isDirty`/`canSave` pattern AGENTS.md warns about, so it went. If a
    /// confirmation dialog is ever wanted back, the staging step is what it needs, and
    /// `cancel` is three lines.
    func remove(_ batch: CalendarEventBatch) {
        pendingDeletion = [batch]
    }

    func confirmDelete() {
        guard !pendingDeletion.isEmpty else { return }
        store.send(.deleteBatches(pendingDeletion))
        pendingDeletion = []
    }

    /// `mergeKey`, not `pendingID`: the card was rendered from whatever the registry held
    /// when the list last drew, and a write landing in between re-mints every row's
    /// `pendingID`. The persisted id the card was drawn with still names the same row.
    func open(_ batch: CalendarEventBatch) {
        store.send(.openBatch(id: batch.mergeKey))
    }

    func startNewBatch(on day: Date) {
        store.send(.startNewBatch(on: day))
    }
}
