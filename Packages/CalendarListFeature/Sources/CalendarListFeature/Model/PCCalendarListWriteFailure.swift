//
//  PCCalendarListWriteFailure.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 11.10.2026.
//

import Foundation

/// A calendar-list write that did not land.
///
/// A value, not an event, for the same reason `PCFailedSave` is one: **the thing that failed is
/// the thing that has to be retried.** Re-running "whatever the user last asked for" is not the
/// same operation — the archive undo, for instance, has to re-archive that same calendar, and by
/// the time the failure is shown the list may have moved on.
///
/// Deliberately `Error`-free of any user-facing wording. What went wrong is this package's
/// business; what to *say* about it belongs to whoever presents it. That is the same split
/// `PCFailedSave` keeps, and it is why `message` is the raw error rather than a sentence.
public struct PCCalendarListWriteFailure: Equatable, Sendable {
    /// What was attempted. Decides which retry runs and what the toast offers.
    public enum Operation: Equatable, Sendable {
        case create(name: String)
        case rename(calendarID: Int64, newName: String)
        case archive(calendarID: Int64)
        case restore(calendarID: Int64)
        case permanentlyDelete(calendarID: Int64)
    }

    public let operation: Operation

    /// The calendar's name at the time, so a toast can name it without another read that might
    /// itself fail. `nil` for a create, where the calendar does not exist yet.
    public let calendarName: String?

    /// The raw error. Best available fallback only — see the type comment.
    public let message: String

    public init(operation: Operation, calendarName: String?, message: String) {
        self.operation = operation
        self.calendarName = calendarName
        self.message = message
    }
}

extension Error {
    /// The best available user-facing fallback for a storage error.
    ///
    /// Shared so every write in this package says the same thing about the same kind of
    /// failure. ObjectBox throws whatever it throws, which is not something to show a user, so
    /// this prefers a real `LocalizedError` description and falls back to the type name rather
    /// than surfacing a raw message.
    var pcUserFacingDescription: String {
        (self as? LocalizedError)?.errorDescription ?? String(describing: Self.self)
    }
}
