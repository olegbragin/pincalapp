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
/// It takes the *previous* state as well as the post-action one, because most of these
/// decisions are about what changed rather than about what was asked: `commitTapped`
/// writes only if the merge actually moved `batches`, and `syncCalendar` writes only if an
/// adoption reassigned an id. Asking "did this action mean to write?" would make both
/// write when nothing changed.
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
            )
        ]
    }

    switch action {
    case .commitTapped:
        // A rejected commit — unsavable batch, no assembly — leaves `batches` alone, and
        // that is precisely how "nothing to write" is recognised without a guard of its
        // own here.
        return next.batches == previous.batches ? [] : write()

    case .saveTapped:
        // A rejected `saveTapped` is likewise a no-op transition, and a rejected one
        // cannot have emitted a navigation either. Guarding would duplicate the reducer's
        // decision.
        return next == previous ? [] : write()

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

    case .setBatchName, .setBatchColor, .toggleDay, .removeEvent,
         .setEventName, .setEventDate, .setEventColor, .saveEventTapped,
         .openEvent, .discardEventTapped, .openBatch, .startNewBatch,
         .dayTappedInCalendar, .backTapped, .closeTapped, .cancelTapped,
         .ensureAssemblyStarted, .navigationRequestHandled, .resetSession,
         .setMultiSelectMode, .setMultiSelectColor, .confirmMultiSelectTapped,
         .cancelMultiSelectTapped, .setEditorYear, .setScrollAnchor:
        // Everything here is staged or view-only. Touching a batch in the editor must not
        // write; only committing or saving does. `confirmMultiSelectTapped` builds a staged
        // assembly but does not commit it, so it is inert too — the write happens when the
        // editor's own save runs.
        return []
    }
}
