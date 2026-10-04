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

    var eventBatches: [CalendarEventBatch] {
        store.state.dayBatches
    }

    var selectedDay: Date? {
        store.state.day
    }

    // MARK: - Commands

    /// Stages a batch for deletion. It stays in the list until `confirmDelete`, which is
    /// what lets `cancel` change its mind — and with a computed projection there is
    /// nothing to put back, because it was never removed locally.
    func remove(_ batch: CalendarEventBatch) {
        pendingDeletion = [batch]
    }

    func confirmDelete() {
        guard !pendingDeletion.isEmpty else { return }
        store.send(.deleteBatches(pendingDeletion))
        pendingDeletion = []
    }

    func cancel() {
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
