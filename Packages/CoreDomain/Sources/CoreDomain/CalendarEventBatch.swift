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

    public var id: UUID {
        pendingID
    }

    public var isPersisted: Bool {
        persistedID != nil
    }

    public var isEmpty: Bool {
        events.isEmpty
    }

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
    public var date: Date? {
        events.first?.date
    }

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

    /// Whether this row could be an earlier state of `other`, used to recognise a staged
    /// batch among the rows that came back from a reload.
    ///
    /// The looser sibling of `hasSameContent(as:using:)`, and deliberately so. Matching a
    /// staged batch to its persisted row across a reload is the only identity mechanism
    /// available — a DTO carries no `pendingID`, so the mapper mints a fresh one per row
    /// per load and the two keys can never be equal — which makes the matcher a heuristic
    /// and the heuristic has to survive the write it is matching. The row in the database
    /// is the batch *as of the write*, and by the time the reload lands the staged batch
    /// has usually grown a day or two. Requiring equal day sets meant a tap arriving
    /// mid-round-trip left the batch permanently unrecognised, and every edit after it
    /// appended a duplicate row instead of updating the one it already had.
    ///
    /// So: same name, same colour, and this row's days are among `other`'s. A subset rather
    /// than equality, which is what makes "the shape it had when we wrote it" expressible.
    ///
    /// Names and colours are the guard against matching the wrong row, so they stay exact —
    /// only the day list is relaxed.
    ///
    /// Two empties match. That is not a loosening of the rule above so much as the one case
    /// where there is nothing to be loose about: an empty batch has no days to compare, so
    /// requiring non-empty on both sides left exactly the rows most worth identifying — a
    /// session that has been emptied, and the stale row it is about to delete — unable to match
    /// anything. Since adoption is what lets the delete find the row by key, refusing here left
    /// an event-less row in the database with no way to name it.
    ///
    /// The risk is deleting an unrelated empty row that shares a name and a colour. An empty row
    /// is already a defect — `saveCalendar` never writes one, since `resolved()` returns `nil`
    /// for a batch with no events — so there is nothing valuable to lose, and the alternative is
    /// a row nothing can ever remove.
    public func isSnapshot(of other: CalendarEventBatch, using dataProvider: PCCalendarDataProvider) -> Bool {
        guard name == other.name, colorName == other.colorName else {
            return false
        }
        if events.isEmpty, other.events.isEmpty {
            return true
        }
        guard !events.isEmpty, !other.events.isEmpty else {
            return false
        }
        return events.allSatisfy { event in
            other.events.contains { dataProvider.isSameDay($0.date, event.date) }
        }
    }

    /// Identity-free comparison, used to recognise a staged batch among the rows that
    /// came back from a reload. Mirrors what
    /// `PCEventsSelectionManager.contentEquals` does, on domain types.
    ///
    /// Days are compared, never instants, at both levels. A row read back through the mapper
    /// carries whatever time component the DTO held, and so does a staged batch — an event's
    /// `date` is no longer truncated to its day, because that truncation was quietly
    /// discarding the time of day the user had picked (§ the event editor's picker). So
    /// comparing the two by instant equality would mean a staged batch and its own
    /// persisted row stop matching the moment a time is set, and the adoption in §6.5 could
    /// never fire. The per-event comparison has always been day-granular; this brings the
    /// batch-level check in line with it.
    public func hasSameContent(as other: CalendarEventBatch, using dataProvider: PCCalendarDataProvider) -> Bool {
        guard name == other.name,
              colorName == other.colorName,
              events.count == other.events.count,
              !events.isEmpty
        else {
            return false
        }
        // `date` is derived from `events.first`, and both are non-empty and the same
        // length here, so both are non-nil.
        guard
            let day = date,
            let otherDay = other.date,
            dataProvider.isSameDay(day, otherDay)
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
