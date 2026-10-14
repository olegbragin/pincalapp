//
//  CalendarListEffects.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 14.10.2026.
//

import Foundation
import CoreDomain

/// Something the world has to be told about, derived from a state transition.
///
/// The second pure function, and the answer to "how does a *pure* reducer trigger a write?"
/// — it does not. This reads the transition and says what should happen; only
/// `CalendarListStore` executes it.
public enum CalendarListEffect: Equatable, Sendable {
    case load
    case createCalendar(name: String)
    case renameCalendar(calendarID: Int64, newName: String)
    case archiveCalendar(calendarID: Int64)
    case restoreCalendar(calendarID: Int64)
    case permanentlyDeleteCalendar(calendarID: Int64)
    /// Tell the owner a calendar left the visible set, so it can close the detail column.
    case announceRemoval(Int64)
    /// Stop the archive window's clock.
    ///
    /// An effect rather than something the reducer can do, because the countdown is a timer
    /// and the reducer is pure. It has to be explicit: without it, tapping Undo clears the
    /// toast in state while the clock runs on and fires `.undoWindowElapsed` seconds later
    /// against a window that no longer exists.
    case cancelArchiveWindow
}

/// Derives the effects of one transition.
///
/// Takes the *previous* state as well as the post-action one, because two decisions here are
/// about what changed rather than about what was asked:
///
/// - `retryWriteFailure` reads the operation it must re-run out of `previous.writeFailure`,
///   which this action deliberately cleared. Asking "did this action mean to write?" could not
///   produce that at all — there is no operation named anywhere else.
/// - `changeApplied` announces a removal only when the list actually lost the calendar, so a
///   change about another mode's contents cannot close a column the user is still looking at.
///
/// The second point is load-bearing and was once wrong. A permanent delete that *failed* used
/// to still close the detail column, tearing down a screen over a row that never went
/// anywhere; because this only fires on an actual removal, and the removal change comes from
/// the cache only on the write's success path, a thrown delete announces nothing.
public func calendarListEffects(
    _ action: CalendarListAction,
    _ previous: CalendarListState,
    _ next: CalendarListState
) -> [CalendarListEffect] {
    switch action {
    case .loadStarted:
        return [.load]

    case let .createTapped(name):
        return [.createCalendar(name: name)]

    case let .renameCommitted(calendarID, newName):
        return [.renameCalendar(calendarID: calendarID, newName: newName)]

    case let .archiveTapped(calendar):
        return [.archiveCalendar(calendarID: calendar.id)]

    case let .restoreTapped(calendar):
        return [.restoreCalendar(calendarID: calendar.id)]

    case let .permanentlyDeleteTapped(calendar):
        return [.permanentlyDeleteCalendar(calendarID: calendar.id)]

    case .undoArchiveTapped:
        // The window always closes, whether or not there is anything to restore.
        guard let pending = previous.pendingArchive else { return [.cancelArchiveWindow] }
        return [.cancelArchiveWindow, .restoreCalendar(calendarID: pending.id)]

    case .retryWriteFailure:
        // Read from `previous`, not `next`: the reducer cleared the failure so that a retry
        // which fails again is recorded afresh instead of leaving a stale one that a later
        // success would wrongly clear.
        guard let failure = previous.writeFailure else { return [] }
        return retryEffects(for: failure.operation)

    case let .changeApplied(change):
        guard case let .removed(calendar) = change,
              !next.calendars.contains(where: { $0.id == calendar.id })
        else { return [] }
        // Announced only after the list has folded it in, so a handler that re-reads the list
        // sees the calendar already gone.
        return [.announceRemoval(calendar.id)]

    case .undoWindowElapsed:
        // The clock has just run out on its own, so there is nothing left to cancel.
        return []

    case .loadSucceeded, .loadFailed, .writeFailed, .archiveConfirmed,
         .displayModeToggled, .addItemTapped:
        // Outcomes of effects already issued, or view-only. Nothing to do.
        return []
    }
}

/// The effect that re-runs one failed operation.
///
/// One function for all five so that Confirm and Cancel cannot drift — which is exactly how
/// an earlier shape of this file ended up staging a batch on one path and not the other.
private func retryEffects(for operation: PCCalendarListWriteFailure.Operation) -> [CalendarListEffect] {
    switch operation {
    case let .create(name):
        return [.createCalendar(name: name)]
    case let .rename(calendarID, newName):
        return [.renameCalendar(calendarID: calendarID, newName: newName)]
    case let .archive(calendarID):
        return [.archiveCalendar(calendarID: calendarID)]
    case let .restore(calendarID):
        return [.restoreCalendar(calendarID: calendarID)]
    case let .permanentlyDelete(calendarID):
        return [.permanentlyDeleteCalendar(calendarID: calendarID)]
    }
}
