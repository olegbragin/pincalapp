//
//  PCEventSelectionEffects.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain

/// Something the world has to be told about, derived from a state transition.
public enum PCEventSelectionEffect: Equatable {
    case writeCalendar(calendarID: Int64, numberOfColumns: Int, batches: [CalendarEventBatch])
}

/// The second pure function, and the answer to "how does a *pure* reducer trigger a
/// write?" — it does not. This reads the transition and says what should happen; only the
/// store executes it (§7.2).
///
/// It takes the *previous* state as well as the post-action one, because every decision
/// here is about what changed rather than about what was asked: `deleteBatches` writes only
/// if the merge actually moved `batches`, and `syncCalendar` writes only if an adoption
/// reassigned an id. Asking "did this action mean to write?" would make both write when
/// nothing changed.
///
/// There used to be a `saveTapped` arm answering `next == previous`, which was a different
/// question from every other action's — and the wrong one for this feature. Edits persist as
/// they are made, so by the time anything reached a "save" the work was already written and
/// the button could only ever re-write or navigate. That is the checkmark's whole reason for
/// having been redundant, and removing it took the arm with it.
public func pcEventSelectionEffects(
    _ action: PCEventSelectionAction,
    _ previous: PCEventSelectionState,
    _ next: PCEventSelectionState
) -> [PCEventSelectionEffect] {
    func write() -> [PCEventSelectionEffect] {
        [
            .writeCalendar(
                calendarID: next.calendarID,
                numberOfColumns: next.numberOfColumns,
                batches: next.batches
            ),
        ]
    }

    switch action {
    case .deleteBatches:
        return next.batches == previous.batches ? [] : write()

    case .setNumberOfColumns:
        return next.numberOfColumns == previous.numberOfColumns ? [] : write()

    case .syncCalendar:
        // Only when an adoption moved the id. Reloading the same batches is a read, not a
        // write, and writing it back would be a pointless round trip on every sync.
        let adoptedBefore = previous.assembly?.adoptedPersistedID
        let adoptedAfter = next.assembly?.adoptedPersistedID
        return adoptedBefore == adoptedAfter ? [] : write()

    case .backTapped:
        // Writes only when leaving the batch editor deleted an emptied row. Everywhere else
        // Back is navigation: the edits it reveals were each written as they were made, so a
        // transition that does not move `batches` genuinely has nothing to persist. This is
        // the whole of what `saveTapped` contributed here, minus the arm that re-merged a
        // row the `editing` path had already merged.
        return next.batches == previous.batches ? [] : write()

    case .setBatchName, .setBatchColor, .toggleDay, .removeEvent,
         .setEventName, .setEventDate, .setEventColor,
         .startNewBatch, .dayTappedInCalendar, .confirmMultiSelectTapped,
         .setMultiSelectColor, .cancelMultiSelectTapped:
        // These merge into `batches` as they are made, so the write is already implied by
        // the state changing. The shared test is the same one every other writing action
        // uses: did the merge actually move anything. That is also what keeps an edit that
        // did not change the row from becoming a pointless write — renaming a batch to the
        // name it already has produces an identical row, so there is nothing to persist.
        //
        // `cancelMultiSelectTapped` is here rather than in the navigation arm below because it
        // is now also a *delete*: a calendar switch dispatches it, and ending a session whose
        // days were all toggled back off has to remove the row. Normally that finds nothing —
        // the tap that removed the last day already did it — so the shared test keeps the
        // common case write-free and only speaks when the row actually moves.
        return next.batches == previous.batches ? [] : write()

    case .openEvent, .discardEventTapped, .openBatch,
         .closeTapped, .cancelTapped,
         .ensureAssemblyStarted, .navigationRequestHandled, .resetSession,
         .setMultiSelectMode,
         .setEditorYear, .setScrollAnchor:
        // Staging, navigation, or view-only. `openEvent` copies a row into a draft without
        // changing it; `discardEventTapped` drops that draft; the rest move between stages.
        // None of them alter a batch, so none of them have anything to write.
        return []
    }
}
