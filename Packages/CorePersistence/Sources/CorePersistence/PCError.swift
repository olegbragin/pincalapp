//
//  PCError.swift
//  CorePersistence
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation

/// A failure reduced to what a report can group on.
///
/// Three fields, no more. Everything else about a failure is either already available where it
/// is reported, or too large to keep: `PCFailedSave` carries the whole batch set precisely so it
/// can be *replayed*, and none of that belongs in a table that is read by a person later. What a
/// report needs is which thing failed, what was attempted, and what came back.
public struct PCErrorRecord: Equatable, Sendable {
    /// Which thing was being operated on.
    public var subject: PCErrorSubject

    /// What was attempted, as a grouping label.
    ///
    /// A `String` rather than an enum on purpose. This is a label a report is grouped by, and a
    /// new failure mode should be reportable without editing this package to declare it first —
    /// which is the whole reason the protocol below can be adopted from *above*, in the app
    /// target, rather than by every package depending on this one.
    public var operation: String

    /// Best available description. Never ObjectBox text verbatim — see `pcFallbackMessage`.
    public var message: String

    /// When the failure happened.
    ///
    /// Stamped by the error, not by whatever records it. A write that fails at 10:00:00 and is
    /// only recorded at 10:00:03 — easy on a loaded device, where the failure is reported from a
    /// continuation rather than at the throw site — has to report the moment it went wrong, or
    /// the table's ordering stops describing the sequence of events that produced it.
    public var timestamp: Date

    public init(
        subject: PCErrorSubject,
        operation: String,
        message: String,
        timestamp: Date = Date()
    ) {
        self.subject = subject
        self.operation = operation
        self.message = message
        self.timestamp = timestamp
    }
}

/// What a failure was about.
///
/// `.unknown` is not a shrug: a create has no id yet, because the row it would name does not
/// exist. Reporting it as `.calendar(id: 0)` would put a real-looking id next to unrelated
/// failures and make the two look related.
public enum PCErrorSubject: Equatable, Sendable {
    case calendar(id: Int64)
    case batch(id: Int64)
    case storage
    case unknown
}

/// The shape every failure in this app is reduced to before it is recorded.
///
/// Declared here because this package is where recording happens, but **conformance is not
/// confined to this package** — and for most error types it cannot be. `PCCalendarListWriteFailure`
/// belongs to `CalendarListFeature` and `PCFailedSave` to `SingleCalendarFeature`, neither of which
/// depends on this one, and asking them to would invert the layering: a feature package reaching
/// into an ObjectBox-tied infrastructure package to describe its own failures.
///
/// Swift's retroactive conformance solves that without any new dependency. A module that can see
/// both the type and the protocol may conform them, so the app target — which imports every
/// package — declares the conformances for the feature-owned types in one file. See
/// `PPErrorConformance.swift`.
///
/// One method rather than three requirements, and that is a constraint rather than a preference:
/// `PCCalendarListWriteFailure` already has a stored `operation` of its own enum type, so a
/// requirement named `operation` of any other type cannot be satisfied by it, and the type cannot
/// declare a second member by that name. The record carries the field instead, which keeps the
/// field names on the thing that is actually stored and displayed.
public protocol PCError: Error {
    /// This failure, reduced to what a report needs.
    func pcRecord() -> PCErrorRecord
}

public extension Error {
    /// The best available description when nothing more specific is available.
    ///
    /// Shared so every failure says the same thing about the same kind of error. ObjectBox
    /// throws whatever it throws, which is not something to show a user or to put in a report, so
    /// this prefers a real `LocalizedError` description and falls back to the type name rather
    /// than surfacing raw text.
    var pcFallbackMessage: String {
        (self as? LocalizedError)?.errorDescription ?? String(describing: Self.self)
    }
}
