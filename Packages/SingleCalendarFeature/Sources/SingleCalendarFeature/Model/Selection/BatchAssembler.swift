//
//  BatchAssembler.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// The unit of work on the assembly line: a batch being edited, plus where it came from.
///
/// A pure value. No store, no clock, no I/O, and every transformation returns a new
/// instance rather than mutating — which is what makes the whole edit/merge/resolve path
/// testable without a view, a repository, or an actor.
///
/// It exists to hold identity in one place. Today that job is spread across three
/// mechanisms in `PCEventsSelectionManager` — `BatchMergeKey`, the
/// `persistedIDsByPendingTimestamp` table, and `contentEquals` — and they disagree with
/// each other. Here it is one `mergeKey` on the value and one `resolved(against:)`, and
/// the duplicate-batch bug in §16 cannot be expressed.
///
/// It is `Sendable` so it can sit in state that a pure reducer compares. `DSKit` is
/// already a dependency of this package, and `PCColorOption` is the only reason the type
/// is not in `CoreDomain`.
public struct BatchAssembler: Equatable, Sendable {
    public private(set) var batch: CalendarEventBatch

    /// Where this assembly entered the line. `.new` was started by the user;
    /// `.existing` was opened from a row already in the registry.
    public private(set) var origin: Origin

    /// Set when a reload revealed this assembly's batch already exists in the store
    /// under a different id, so a later commit updates that row instead of appending a
    /// duplicate. Set by the `syncCalendar` adoption in §6.5, applied by
    /// `resolved(against:)`.
    public var adoptedPersistedID: Int64?

    public enum Origin: Equatable, Sendable {
        case new
        case existing(pendingID: UUID)
    }

    public var isNew: Bool { origin == .new }

    /// A batch is only worth writing with a name, a colour, and at least one day. The
    /// name check is what stops a freshly-toggled day from being committed as a row of
    /// blank events.
    public var canSave: Bool {
        !batch.name.isEmpty && !batch.colorName.isEmpty && !batch.events.isEmpty
    }

    private init(batch: CalendarEventBatch, origin: Origin) {
        self.batch = batch
        self.origin = origin
    }

    // MARK: - Identity

    /// A brand-new batch holding one day, unnamed and uncoloured.
    ///
    /// The anchor is normalised to the start of its day, because a batch is day-granular
    /// and every later comparison — `occurs(on:using:)`, `hasSameContent(as:using:)`,
    /// the day-marker projection — keys on a start-of-day value.
    public static func new(
        anchor: Date,
        colorName: String,
        using dataProvider: PCCalendarDataProvider
    ) -> BatchAssembler {
        let day = dataProvider.startOfDay(for: anchor)
        let batch = CalendarEventBatch(
            name: "",
            colorName: colorName,
            events: [placeholder(on: day, colorName: colorName)]
        )
        return BatchAssembler(batch: batch, origin: .new)
    }

    /// A brand-new batch holding one placeholder per selected day, for the multi-select
    /// path. `days` are sorted, so the result does not depend on the order they were
    /// tapped in.
    public static func new(
        all days: [Date],
        color: PCColorOption?,
        using dataProvider: PCCalendarDataProvider
    ) -> BatchAssembler {
        let colorName = color?.colorName ?? ""
        let events = days
            .map { placeholder(on: dataProvider.startOfDay(for: $0), colorName: colorName) }
            .sorted { $0.date < $1.date }
        let batch = CalendarEventBatch(name: "", colorName: colorName, events: events)
        return BatchAssembler(batch: batch, origin: .new)
    }

    /// Opens a batch already in the registry for editing. Its `pendingID` is recorded so
    /// the commit can find the row again by `mergeKey`.
    public static func existing(_ batch: CalendarEventBatch) -> BatchAssembler {
        BatchAssembler(batch: batch, origin: .existing(pendingID: batch.pendingID))
    }

    // MARK: - Transformations

    public func renaming(_ name: String) -> BatchAssembler {
        var copy = self
        copy.batch = batch.with(name: name)
        return copy
    }

    /// Recolours the batch and every event in it.
    ///
    /// Events are updated unconditionally, including when the colour is cleared.
    /// `CalendarEventBatch.with(colorName:propagateToEvents:)` deliberately skips
    /// propagation for an empty name, which is right for a partially-typed batch but
    /// wrong here: the day markers are projected from *event* colours, so a batch
    /// recoloured to nothing while its events kept the old colour would keep painting
    /// markers for a colour the batch no longer has.
    public func recoloring(_ color: PCColorOption?) -> BatchAssembler {
        let colorName = color?.colorName ?? ""
        var copy = self
        copy.batch = batch
            .with(colorName: colorName)
            .with(events: batch.events.map { $0.with(colorName: colorName) })
        return copy
    }

    /// Turns a day on if it is off, off if it is on.
    ///
    /// The removal runs first and unconditionally. That is what makes "a day never holds
    /// two events" true by construction rather than by argument: whatever was on the day
    /// is gone before anything is added, so no input can produce a second event there.
    /// The append is then conditional — if the removal took something, this was a toggle
    /// *off* and we stop.
    public func toggling(day: Date, using dataProvider: PCCalendarDataProvider) -> BatchAssembler {
        let target = dataProvider.startOfDay(for: day)
        let remaining = batch.events.filter { !dataProvider.isSameDay($0.date, target) }
        var copy = self
        if remaining.count == batch.events.count {
            // Nothing was on the day, so this turns it on.
            copy.batch = batch.with(events: remaining + [Self.placeholder(on: target, colorName: batch.colorName)])
        } else {
            copy.batch = batch.with(events: remaining)
        }
        return copy
    }

    public func removingEvent(pendingID: UUID) -> BatchAssembler {
        let remaining = batch.events.filter { $0.pendingID != pendingID }
        guard remaining.count != batch.events.count else { return self }
        var copy = self
        copy.batch = batch.with(events: remaining)
        return copy
    }

    /// Folds an edited event back into the batch.
    ///
    /// One expression covers both cases, because both questions have the same answer.
    /// An event is replaced when it is already in the batch *by* `pendingID`, and a day
    /// is vacated when the incoming event lands on one that already holds an event. So
    /// the surviving events are those that are neither the same event nor on the
    /// incoming event's day, and the incoming event is appended. That is what makes
    /// moving an event onto an occupied day a move rather than a duplicate — and it
    /// holds even when the edit changes an existing event's date onto a taken day, which
    /// the pendingID-only rule would let through.
    public func applying(_ event: CalendarEvent, using dataProvider: PCCalendarDataProvider) -> BatchAssembler {
        let incoming = event.with(date: dataProvider.startOfDay(for: event.date))
        let survivors = batch.events.filter {
            $0.pendingID != incoming.pendingID && !dataProvider.isSameDay($0.date, incoming.date)
        }
        var copy = self
        copy.batch = batch.with(events: survivors + [incoming])
        return copy
    }

    public func adopting(persistedID: Int64?) -> BatchAssembler {
        var copy = self
        copy.adoptedPersistedID = persistedID
        return copy
    }

    /// The row to write, or `nil` when the batch has been emptied and the calendar's
    /// row must go instead.
    ///
    /// This is the single home of the duplicate-batch logic, replacing the old
    /// `BatchMergeKey` / `persistedIDsByPendingTimestamp` / `contentEquals` trio. The id
    /// is `adoptedPersistedID ?? batch.persistedID`, and §5.4's original
    /// `resolved(against: batches)` — which looked the row up in the registry by
    /// `mergeKey` — was removed as unreachable. The proof is short: if some row `r`
    /// matches `batch.mergeKey`, then
    ///
    /// - when `batch.persistedID` is non-nil the key is `.persisted(id)`, so
    ///   `r.persistedID == batch.persistedID`, and
    /// - when it is nil the key is `.pending(uuid)`, which never equals
    ///   `.persisted(_)`, so `r.persistedID` is nil as well.
    ///
    /// Either way the lookup returned exactly what the batch already carried. Identity
    /// has two real sources and no third: an explicit reassignment from a reload, which
    /// only `adoptedPersistedID` knows, and the id the batch was opened with. Matching a
    /// batch across a reload by *content* is §6.5's job, and it is the only mechanism
    /// that can — a DTO carries no `pendingID`, so the mapper mints a fresh one per row
    /// per load and a reloaded row's key can never equal a staged one's.
    public func resolved() -> CalendarEventBatch? {
        guard !batch.isEmpty else { return nil }
        return batch.with(persistedID: adoptedPersistedID ?? batch.persistedID)
    }

    // MARK: - Placeholder

    /// An event occupying a day but not yet named. An empty `name` is what marks it as
    /// unedited, and is what `saveEventTapped`'s "name non-empty" guard rejects.
    private static func placeholder(on day: Date, colorName: String) -> CalendarEvent {
        CalendarEvent(name: "", date: day, colorName: colorName)
    }
}
