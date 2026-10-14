//
//  CalendarListAction.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 14.10.2026.
//

import Foundation
import CoreDomain

/// Everything that can happen to the calendar-list screen.
///
/// An action is a *statement of intent*, not a command: it says what the user did, and the
/// reducer decides what that means. A view never assigns state and never asks what a change
/// did — it sends, and reads the result.
///
/// No case carries an `Error`. State has to stay `Equatable` for the reducer tests, and an
/// error is neither `Equatable` nor something a transition should be described by. Failures
/// reach the owner through the effect that produced them instead: `loadFailed` records *that*
/// it failed, while the raw error goes to `onLoadFailed` from the failing effect, which is the
/// only place that still has it.
public enum CalendarListAction: Equatable {
    // MARK: Loading

    case loadStarted
    case loadSucceeded([PinCalendar])
    /// Deliberately carries nothing — see the type comment. The raw error is raised to
    /// `onLoadFailed` by the effect that caught it.
    case loadFailed

    // MARK: Writes

    case createTapped(name: String)
    case renameCommitted(calendarID: Int64, newName: String)
    case archiveTapped(PinCalendar)
    case restoreTapped(PinCalendar)
    case permanentlyDeleteTapped(PinCalendar)
    /// Re-runs the operation named by `writeFailure`, exactly as it was attempted.
    case retryWriteFailure

    // MARK: Write outcomes

    /// An archive landed, so the undo window may now open.
    ///
    /// A separate action from `archiveTapped` because the two are minutes apart and only one
    /// of them may be answered with a toast. Raising the toast here rather than on the tap is
    /// the whole reason the window starts when there is genuinely something to undo.
    case archiveConfirmed(PinCalendar)
    /// A write did not land, with the failure that has to be retried.
    case writeFailed(PCCalendarListWriteFailure)

    // MARK: The archive undo window

    case undoArchiveTapped
    /// Raised by `PCTimeoutProgress` when the window runs out.
    case undoWindowElapsed

    // MARK: View-only

    case displayModeToggled
    case addItemTapped

    // MARK: The change feed

    /// One entry of `CalendarManaging.changes()`, folded into `calendars`.
    case changeApplied(PinCalendarChange)
}
