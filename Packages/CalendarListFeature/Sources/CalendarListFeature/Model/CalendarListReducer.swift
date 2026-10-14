//
//  CalendarListReducer.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 14.10.2026.
//

import Foundation
import CoreDomain

/// The one pure function that decides what an action means.
///
/// A declared `func` rather than a `public let` of function type, for the reason
/// `pcEventSelectionReducer` gives: a global `let` of function type has to be `Sendable` in
/// Swift 6, and `PinCalendar` reaches a `Date` through `PCCalendarDataProvider`, which is not.
///
/// Pure in the strong sense — it reads only its arguments and touches nothing outside them.
/// Every effectful step is derived separately by `calendarListEffects`, which is what lets a
/// test assert a transition with no port, no timer and no view.
public func calendarListReducer(
    _ state: CalendarListState,
    _ action: CalendarListAction
) -> CalendarListState {
    var next = state

    switch action {
    case .loadStarted:
        // The spinner is a function of "a load is running" *and* "there is nothing to show",
        // and that conjunction used to be evaluated in the view body. Deciding it here states
        // the rule once, and a pull-to-refresh over a populated list cannot flicker the whole
        // screen to a spinner.
        next.beginLoadingIfNothingToShow()
        // `loadFailure` is deliberately untouched, so the toast survives the retry it was
        // offering. Only `.loadSucceeded` clears it.

    case let .loadSucceeded(calendars):
        next.calendars = calendars
        next.stage = .content
        next.loadFailure = false

    case .loadFailed:
        // `calendars` is left exactly as it was: a failed read is not evidence that the user
        // has no calendars, so the last known list stays visible behind the error rather than
        // being replaced by a blank one that reads as data loss.
        next.loadFailure = true

    case let .createTapped(name):
        // Only meaningful for the state the view is actually in, and `writeFailure` is
        // cleared here so a previous create failure does not keep offering its own Retry
        // while a new one is in flight.
        next.writeFailure = nil
        next.beginLoadingIfNothingToShow()
        _ = name

    case let .renameCommitted(calendarID, newName):
        guard let idx = next.calendars.firstIndex(where: { $0.id == calendarID }) else { return state }
        // Optimistic, and reverted by the effect if the write fails. The card has already
        // shown the new name by the time this arrives, so the list has to agree with it
        // rather than lag behind what is on screen.
        next.calendars[idx].name = newName

    case .archiveTapped:
        // Nothing moves until the write lands. This arm used to set `pendingArchive`, which
        // made the toast assert "X archived" before anything had been written — a failed write
        // then left the calendar sitting in the active list under a banner saying it had gone.
        // The effect dispatches `.archiveConfirmed` or `.writeFailed` instead.
        next.writeFailure = nil

    case .restoreTapped, .permanentlyDeleteTapped:
        next.writeFailure = nil

    case .retryWriteFailure:
        // Cleared before the effect runs, so a failure that recurs is recorded afresh rather
        // than leaving a stale one that a later success would wrongly clear.
        next.writeFailure = nil

    case .undoArchiveTapped:
        // The calendar comes back through the change feed rather than being pushed into the
        // list here: the restore publishes a change, and re-reading to satisfy it would
        // discard its own result. What the tap does do is end the window, so a failed restore
        // cannot leave a toast offering to undo something already undone.
        next.pendingArchive = nil
        next.isArchiveToastPresented = false

    case .undoWindowElapsed:
        next.pendingArchive = nil
        next.isArchiveToastPresented = false

    case .displayModeToggled:
        next.displayMode = next.displayMode.toggled

    case .addItemTapped:
        break

    case let .archiveConfirmed(calendar):
        next.pendingArchive = calendar
        next.isArchiveToastPresented = true

    case let .writeFailed(failure):
        next.writeFailure = failure

    case let .changeApplied(change):
        next = apply(change, to: next)
    }

    return next
}

/// Folds one change into the visible list.
///
/// A store emits changes relative to *its own* current list, which is whichever
/// active-or-archived set was loaded last — and that is not necessarily this screen's `mode`.
/// Two cases make that visible: restoring a calendar while viewing Archived is reported as an
/// *addition* even though the result is that it leaves this list, and a refresh can carry the
/// other mode's contents. So rather than trusting the operation's shape, every change is
/// resolved against the mode: a calendar that belongs in the visible set is upserted, and one
/// that does not is taken out. That makes the screen correct against any store, and
/// independent of which list the store happened to have loaded.
private func apply(_ change: PinCalendarChange, to state: CalendarListState) -> CalendarListState {
    var next = state

    func isVisible(_ calendar: PinCalendar) -> Bool {
        switch next.mode {
        case .active: return !calendar.isArchived
        case .archived: return calendar.isArchived
        }
    }

    switch change {
    case let .refreshed(list):
        next.calendars = list.filter(isVisible)
    case let .added(calendar), let .changed(calendar):
        if isVisible(calendar) {
            if let idx = next.calendars.firstIndex(where: { $0.id == calendar.id }) {
                next.calendars[idx] = calendar
            } else {
                next.calendars.append(calendar)
            }
        } else {
            next.calendars.removeAll { $0.id == calendar.id }
        }
    case let .removed(calendar):
        next.calendars.removeAll { $0.id == calendar.id }
    }

    // A create that lands while the screen was showing a spinner is the one thing that can
    // fill it from outside a load, so the spinner is taken down here rather than being left
    // until the next `.loadSucceeded` that this screen may never send.
    if next.stage == .loading, !next.calendars.isEmpty {
        next.stage = .content
    }
    return next
}

private extension CalendarListState {
    /// The spinner shows for a load with nothing behind it, and nowhere else.
    ///
    /// Guarded on `calendars.isEmpty` because that is what makes it a *loading* screen rather
    /// than a refresh: replacing a populated list with a spinner on every pull-to-refresh is
    /// what the view's `isLoading && calendars.isEmpty` condition was avoiding, and keeping
    /// the rule only in the reducer is what stops the two from drifting apart.
    mutating func beginLoadingIfNothingToShow() {
        if calendars.isEmpty {
            stage = .loading
        }
    }
}
