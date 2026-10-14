//
//  CalendarListState.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 14.10.2026.
//

import Foundation
import CoreDomain

/// The whole of the calendar-list screen's state, as a value.
///
/// Mutated only by `calendarListReducer`, so every transition can be read in one place and
/// asserted on without constructing a view model or a fake port. This is the same split
/// `PCEventSelectionState` has for the batch-assembly line.
///
/// Two things are deliberately **not** here, because a value cannot hold them:
///
/// - `archiveCountdown` is a `PCTimeoutProgress`, which owns a timer and a completion
///   handler. It lives on `CalendarListStore`, and the store feeds its completion back in as
///   `.undoWindowElapsed` so the *decision* to end the window is still a state transition.
/// - The card view models and the add-calendar sheet's view model are caches keyed by
///   identity, not screen state. They live on `CalendarListViewModel`.
///
/// Note what `loadFailure` is *not* folded into `Stage`: it is orthogonal to it. A failed
/// load keeps the last known list on screen and its toast persists across a retry, so "the
/// last load failed" and "a load is in flight and there is nothing to show" are independent
/// facts. Collapsing them into one enum would have to pick a winner and would make the toast
/// disappear the moment a retry began.
public struct CalendarListState: Equatable {
    /// What the list is showing.
    public enum Stage: Equatable {
        /// A load is in flight and there is nothing to show yet, so the screen is a spinner.
        case loading
        /// A load has succeeded. The list may still be empty — that is a fact about the data.
        case content
    }

    /// Which set this screen shows. Configuration rather than something the user changes,
    /// but it lives here because the reducer needs it: a change arriving on the feed is
    /// resolved against the mode to decide whether it belongs in the visible list, and a
    /// pure function cannot read it from anywhere else.
    public var mode: CalendarListMode

    public var stage: Stage = .loading
    public var calendars: [PinCalendar] = []
    public var displayMode: DisplayMode = .list

    /// The last load failed, cleared by the next successful one.
    ///
    /// Sticky across a retry: `loadStarted` does not clear it, so the toast stays up while the
    /// user is trying again and only disappears when a load actually lands. Held as state
    /// because "the list is empty" and "the list could not be read" are different facts that a
    /// view cannot tell apart by looking at `calendars`.
    public var loadFailure = false

    /// A write that failed, cleared by the next successful one or by retrying.
    ///
    /// Separate from `loadFailure` because the two have different remedies: a failed *read* is
    /// retried as-is, whereas a failed *write* has to be retried as the specific operation it
    /// was — and a permanent delete must be asked for again rather than replayed.
    public var writeFailure: PCCalendarListWriteFailure?

    /// The calendar awaiting the archive timeout; nil when no toast is pending.
    public var pendingArchive: PinCalendar?
    public var isArchiveToastPresented = false

    public init(mode: CalendarListMode) {
        self.mode = mode
    }
}
