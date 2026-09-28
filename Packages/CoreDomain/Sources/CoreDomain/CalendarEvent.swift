//
//  CalendarEvent.swift
//  CoreDomain
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation

/// One event inside a `CalendarEventBatch`.
///
/// This replaces `EventDataSource`, which was declared as a persistence DTO but was
/// never actually persisted: both DTO initialisers hard-set its `timestamp` to `nil`.
/// That field was a session identity wearing a DTO's clothes, so it becomes
/// `pendingID` here and the persistence layer stops exposing it.
///
/// This is a plain value and depends on nothing. It does not hold a
/// `PCCalendarDataProvider` and does not need one to be constructed — `Date` already
/// says which day it is on. A calendar is needed to *compare* two events, and that is
/// a question `CalendarEventBatch.occurs(on:using:)` asks, not something this value
/// has to carry.
///
/// An earlier draft also stored a `dayKey: Date` next to `date`, normalised to the
/// start of its day. That was a second representation of a fact `date` already
/// carried, and it could drift: any setter of `date` had to remember to recompute it.
/// There is one representation now.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Stable identity for the lifetime of the edit session. Never persisted.
    public let pendingID: UUID
    /// The store-assigned id, once known. `nil` until the batch is written.
    public var persistedID: Int64?

    public var name: String
    public var date: Date
    public var colorName: String

    public var id: UUID { pendingID }
    public var isPersisted: Bool { persistedID != nil }

    public init(
        pendingID: UUID = UUID(),
        persistedID: Int64? = nil,
        name: String = "",
        date: Date,
        colorName: String = ""
    ) {
        self.pendingID = pendingID
        self.persistedID = persistedID
        self.name = name
        self.date = date
        self.colorName = colorName
    }

    public func with(name: String) -> CalendarEvent {
        var copy = self
        copy.name = name
        return copy
    }

    public func with(date: Date) -> CalendarEvent {
        var copy = self
        copy.date = date
        return copy
    }

    public func with(colorName: String) -> CalendarEvent {
        var copy = self
        copy.colorName = colorName
        return copy
    }

    /// `pendingID` is `let`, so replacing it needs a full copy rather than a mutation.
    public func with(pendingID: UUID) -> CalendarEvent {
        CalendarEvent(
            pendingID: pendingID,
            persistedID: persistedID,
            name: name,
            date: date,
            colorName: colorName
        )
    }

    public func with(persistedID: Int64?) -> CalendarEvent {
        var copy = self
        copy.persistedID = persistedID
        return copy
    }
}
