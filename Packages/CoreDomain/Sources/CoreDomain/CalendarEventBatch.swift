//
//  CalendarEventBatch.swift
//  CoreDomain
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation

/// How a batch is matched against a committed row.
///
/// This replaces `PCEventsSelectionManager.BatchMergeKey`, whose third case was
/// `unsaved(Int)` built from `batch.hashValue`. Swift seeds `Hasher` per process but
/// re-randomises per hashing operation, so a fresh hash and a stored hash of the same
/// value do not reliably agree — and `commit` compared a fresh `key(for:)` against
/// stored ones to deduplicate. A hash is not an identity.
public enum EventBatchKey: Hashable, Sendable {
    case persisted(Int64)
    case pending(UUID)
}

/// A named group of events belonging to one calendar.
///
/// Replaces `EventBatchDataSource`, which is a persistence DTO. The important change
/// is that `date` is **derived** rather than stored: `AddEditEventBatchViewModel`
/// holds a `date` that `toggleEvent` never updates when it adds a day, so a batch's
/// own date drifts away from its events. Deriving it removes that class of bug
/// instead of documenting it.
public struct CalendarEventBatch: Identifiable, Hashable, Sendable {
    /// Stable identity for the lifetime of the edit session. Never persisted.
    public let pendingID: UUID
    /// The store-assigned id, once known. `nil` until the batch is written.
    public var persistedID: Int64?

    public var name: String
    public var colorName: String
    /// Always sorted ascending by `date`, at most one event per calendar day.
    public var events: [CalendarEvent]

    public var id: UUID { pendingID }
    public var isPersisted: Bool { persistedID != nil }
    public var isEmpty: Bool { events.isEmpty }

    public init(
        pendingID: UUID = UUID(),
        persistedID: Int64? = nil,
        name: String = "",
        colorName: String = "",
        events: [CalendarEvent] = []
    ) {
        self.pendingID = pendingID
        self.persistedID = persistedID
        self.name = name
        self.colorName = colorName
        self.events = events.sorted { $0.date < $1.date }
    }

    /// Identity for matching an assembly against a committed row. Never a hash.
    public var mergeKey: EventBatchKey {
        persistedID.map(EventBatchKey.persisted) ?? .pending(pendingID)
    }

    /// The first event's day, or `nil` when the batch is empty.
    public var date: Date? { events.first?.date }

    public func occurs(on day: Date, using dataProvider: PCCalendarDataProvider) -> Bool {
        events.contains { dataProvider.isSameDay($0.date, day) }
    }

    public func with(name: String) -> CalendarEventBatch {
        var copy = self
        copy.name = name
        return copy
    }

    public func with(colorName: String, propagateToEvents: Bool = true) -> CalendarEventBatch {
        var copy = self
        copy.colorName = colorName
        if propagateToEvents, !colorName.isEmpty {
            copy.events = events.map { $0.with(colorName: colorName) }
        }
        return copy
    }

    public func with(events: [CalendarEvent]) -> CalendarEventBatch {
        var copy = self
        copy.events = events.sorted { $0.date < $1.date }
        return copy
    }

    public func with(persistedID: Int64?) -> CalendarEventBatch {
        var copy = self
        copy.persistedID = persistedID
        return copy
    }

    /// Identity-free comparison, used to recognise a staged batch among the rows that
    /// came back from a reload. Mirrors what
    /// `PCEventsSelectionManager.contentEquals` does, on domain types.
    public func hasSameContent(as other: CalendarEventBatch, using dataProvider: PCCalendarDataProvider) -> Bool {
        guard name == other.name,
              colorName == other.colorName,
              (date ?? .distantFuture) == (other.date ?? .distantFuture),
              events.count == other.events.count,
              !events.isEmpty
        else {
            return false
        }
        return zip(events, other.events).allSatisfy { lhs, rhs in
            lhs.name == rhs.name
                && lhs.colorName == rhs.colorName
                && dataProvider.isSameDay(lhs.date, rhs.date)
        }
    }
}
