//
//  PCCalendarSessionTests.swift
//  PinCalAppTests
//
//  The session's job is to hand out **one store per calendar** and to end that calendar's
//  multi-select session when it is left. Both are load-bearing and neither was exercised
//  anywhere: the app used to build a single store for the whole process, which pinned
//  `state.calendarID` to the first calendar opened and sent a second calendar's taps into the
//  first calendar's row.
//
//  Over a real in-memory ObjectBox rather than a fake port, because the last test here is
//  about the row reaching *storage* — "keep the database clean" is the requirement, and a fake
//  that recorded writes would be asserting the port was called rather than that anything was
//  deleted.
//

import Foundation
import Testing
import CoreDomain
import DSKit
import ObjectBox
import SingleCalendarFeature
// `@testable` for `PP*` entities and the in-memory store factory.
@testable import CorePersistence
@testable import PinCalApp

@MainActor
@Suite("PCCalendarSession")
struct PCCalendarSessionTests {
    private let day = Date(timeIntervalSince1970: 1_780_000_000)

    /// `PCCalendarSession.persistence` is typed `any CalendarPersisting`, so reading rows back
    /// needs the concrete `CalendarStore`. Carried on the fixture rather than down-cast from the
    /// session, so the test reads the port it built instead of reaching through the session.
    private struct Fixture {
        let objectBox: Store
        let cache: CalendarCache
        let session: PCCalendarSession
        let port: CalendarStore

        func close() {
            objectBox.close()
        }
    }

    private func makeFixture() throws -> Fixture {
        let objectBox = try ObjectBoxFactory.makeInMemoryStore(named: "session-\(UUID().uuidString)")
        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: objectBox))
        let calendarStore = CalendarStore(cache: cache)
        let session = PCCalendarSession(
            persistence: calendarStore,
            managing: calendarStore,
            makeEventSelection: { _ in
                PCEventSelectionManager(
                    initialState: PCEventSelectionState(dataProvider: PCCalendarDataProvider()),
                    // A fresh selection manager per calendar, not a shared one. The store writes
                    // `selectedDays` on it and installs a tap listener, so sharing one would let
                    // an editor's selection leak across calendars.
                    persistence: calendarStore,
                    daySelectionManager: PCCalendarDaySelectionManager()
                )
            }
        )
        return Fixture(objectBox: objectBox, cache: cache, session: session, port: calendarStore)
    }

    private func batch(_ name: String, on date: Date, id: Int64? = nil) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: id,
            name: name,
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: date, colorName: "eventColorOption1")]
        )
    }

    // MARK: - One store per calendar

    @Test("Each calendar gets its own store")
    func storesAreDistinctPerCalendar() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let first = fixture.session.eventSelection(for: 1)
        let second = fixture.session.eventSelection(for: 2)

        #expect(first !== second, "two calendars cannot share a store — see the type's doc")
    }

    /// Cached, so returning to a calendar restores its staged edit rather than dropping it.
    ///
    /// Which is only safe because `endSession(for:)` runs on the way out — see the type's doc
    /// for what an uncached-and-unended store leaves behind.
    @Test("A store is cached, so returning to a calendar restores its state")
    func storesAreCached() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let store = fixture.session.eventSelection(for: 7)
        store.send(.syncCalendar(calendarID: 7, batches: [batch("Swim", on: day)]))
        #expect(store.state.batches.count == 1)

        let returned = fixture.session.eventSelection(for: 7)

        #expect(returned === store, "the same instance comes back")
        #expect(returned.state.batches.count == 1, "and the work is still there")
    }

    /// The bug, stated as a test: with one store for the process, the second calendar's rows
    /// were refused and its writes went to the first calendar.
    ///
    /// Two stores make the whole thing unobservable — there is no shared `calendarID` left to
    /// pin — so this asserts the *absence* of the mechanism rather than the presence of the
    /// fix. It is here because the absence is the whole point, and a future "simplification"
    /// back to a single store would otherwise pass every other test in this file.
    @Test("One calendar's batches cannot appear in another calendar's store")
    func batchesDoNotLeakBetweenCalendars() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let first = fixture.session.eventSelection(for: 1)
        let second = fixture.session.eventSelection(for: 2)
        first.send(.syncCalendar(calendarID: 1, batches: [batch("Swim", on: day, id: 1)]))
        second.send(.syncCalendar(calendarID: 2, batches: [batch("Run", on: day, id: 2)]))

        #expect(first.state.batches.map(\.name) == ["Swim"])
        #expect(second.state.batches.map(\.name) == ["Run"])
        #expect(first.state.calendarID == 1)
        #expect(second.state.calendarID == 2)
    }

    /// A store is told its calendar once, on its first sync, and that id is what every write
    /// targets. With one store per calendar there is nothing to confuse it with.
    @Test("A second calendar's sync cannot repoint an existing store")
    func syncCannotRepointAStore() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let store = fixture.session.eventSelection(for: 1)
        store.send(.syncCalendar(calendarID: 1, batches: [batch("Swim", on: day, id: 1)]))

        // Defence in depth: this is unreachable through `eventSelection(for:)`, because
        // calendar 2 gets its own store. If it ever became reachable again, the store would
        // keep calendar 1's rows rather than silently serving calendar 2 out of them.
        store.send(.syncCalendar(calendarID: 2, batches: [batch("Run", on: day, id: 2)]))

        #expect(store.state.calendarID == 1, "the store still belongs to calendar 1")
        #expect(store.state.batches.map(\.name) == ["Swim"], "and still holds calendar 1's rows")
    }

    // MARK: - Ending a session

    /// A calendar with no store yet has nothing to end, and asking is not an error — the
    /// switch path calls this unconditionally.
    @Test("Ending a session for a calendar that was never opened is harmless")
    func endingAnUnknownCalendarIsHarmless() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        fixture.session.endSession(for: 99)
    }

    /// The session a user can no longer see must not come back when they return.
    @Test("Ending a session clears it, so returning to the calendar finds single-select")
    func endingASessionClearsIt() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let store = fixture.session.eventSelection(for: 1)
        store.send(.syncCalendar(calendarID: 1, batches: []))
        store.send(.setMultiSelectMode(true))
        store.send(.setMultiSelectColor(.option2))
        store.send(.dayTappedInCalendar(day))
        #expect(store.state.multiSelectMode)
        #expect(store.state.batches.count == 1)

        fixture.session.endSession(for: 1)

        #expect(!store.state.multiSelectMode, "single-select again")
        #expect(store.state.multiSelectDays.isEmpty)
        #expect(store.state.multiSelectColor == nil)
        #expect(store.state.multiSelectAssembly == nil)
        // The batch had a day, so ending keeps it — ending a session is not undoing it.
        #expect(store.state.batches.count == 1, "the work the user did is not discarded")
    }

    /// The user's requirement: end the session on the way out and delete a batch that has no
    /// days, so the database stays clean.
    ///
    /// Asserted against storage rather than against `state.batches`, because "clean" is about
    /// the database: a registry that says one thing while a stale row sits in ObjectBox is
    /// precisely the case this is for.
    @Test("Tapping a session's days back off and then leaving the calendar leaves storage clean")
    func endingASessionLeavesStorageClean() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        // `createCalendar` returns nothing, so the assigned id is read back the way
        // `CalendarStoreTests` does it rather than guessed.
        try await fixture.cache.createCalendar(name: "Work", year: 2026, numberOfColumns: 3)
        let all = try await fixture.cache.getAllCalendars()
        let calendarID = try #require(all.first { $0.name == "Work" }?.id)

        let store = fixture.session.eventSelection(for: calendarID)
        store.send(.syncCalendar(calendarID: calendarID, batches: []))
        store.send(.setMultiSelectMode(true))
        store.send(.setMultiSelectColor(.option2))
        store.send(.dayTappedInCalendar(day))
        #expect(store.state.batches.count == 1, "setup: the tap wrote the batch")
        await store.flushBeforeLeavingCalendar()
        #expect(try await fixture.port.eventBatches(calendarID: calendarID).count == 1)

        store.send(.dayTappedInCalendar(day)) // the same day again: off
        fixture.session.endSession(for: calendarID)
        await store.flushBeforeLeavingCalendar()

        #expect(store.state.batches.isEmpty, "the registry is empty")
        #expect(!store.state.multiSelectMode, "and the session is over")
        #expect(store.state.multiSelectAssembly == nil)
        #expect(
            try await fixture.port.eventBatches(calendarID: calendarID).isEmpty,
            "so the database is clean too — not merely tidy in memory"
        )
    }

    /// A reload that raced the deletion can put the row back, and the session's key can no longer
    /// name it — the reload re-mints `pendingID`, and `isSnapshot` has nothing to compare
    /// because the assembly is empty while the returning row is the pre-deletion snapshot.
    ///
    /// It is recognised by its **absence** instead: while an emptied session is live, the session
    /// has deleted one row and created none, so a reloaded row the registry has never seen can
    /// only be that one. Matching by name and colour — the obvious alternative — is wrong, because
    /// two untouched default batches share both.
    @Test("A reload that raced the deletion does not bring an emptied session's row back")
    func aRacingReloadCannotResurrectADeletedRow() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try await fixture.cache.createCalendar(name: "Work", year: 2026, numberOfColumns: 3)
        let all = try await fixture.cache.getAllCalendars()
        let calendarID = try #require(all.first { $0.name == "Work" }?.id)

        let store = fixture.session.eventSelection(for: calendarID)
        store.send(.syncCalendar(calendarID: calendarID, batches: []))
        store.send(.setMultiSelectMode(true))
        store.send(.setMultiSelectColor(.option2))
        store.send(.dayTappedInCalendar(day))
        let written = batch("New event", on: day, id: 1)

        // The day comes off, and the row goes with it.
        store.send(.dayTappedInCalendar(day))
        #expect(store.state.batches.isEmpty)

        // …and a reload that was in flight hands it back, re-minted and no longer matchable.
        // This is the whole scenario: the row arrives, and nothing downstream can name it.
        store.send(.syncCalendar(calendarID: calendarID, batches: [written]))
        #expect(store.state.multiSelectAssembly?.batch.isEmpty == true, "an empty session")

        // It does not survive the reload, and the day the user took off is not marked again.
        #expect(
            store.state.batches.isEmpty,
            "the resurrected row is dropped on arrival; got \(store.state.batches.count)"
        )
        let marker = store.state.dayEventColors[store.state.dataProvider.startOfDay(for: day)]
        #expect(
            marker == nil,
            "and the day stays unmarked; got \(String(describing: marker))"
        )
    }

    /// The other half of the same rule: absence cannot swallow a batch the user actually made.
    ///
    /// Two default batches sharing a name and a colour is the case that stopped this being fixed
    /// by name-and-colour, so it is the case worth pinning.
    @Test("An emptied session's reload leaves unrelated batches alone")
    func anEmptiedSessionsReloadKeepsOtherBatches() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let store = fixture.session.eventSelection(for: 1)
        // A pre-existing batch, and the session's own — both named "New event", both the same
        // colour, because that is what an untouched batch looks like.
        let neighbour = batch("New event", on: day.addingTimeInterval(-86400), id: 5)
        store.send(.syncCalendar(calendarID: 1, batches: [neighbour]))
        store.send(.setMultiSelectMode(true))
        store.send(.setMultiSelectColor(.option2))
        store.send(.dayTappedInCalendar(day))
        store.send(.dayTappedInCalendar(day)) // empty the session again
        #expect(store.state.batches.count == 1, "setup: only the neighbour is left")

        // A reload that returns both the neighbour and a row the registry has never seen.
        let stranger = batch("New event", on: day, id: 9)
        store.send(.syncCalendar(calendarID: 1, batches: [neighbour, stranger]))

        #expect(
            store.state.batches.count == 1,
            "the unseen row is the resurrected one and goes; the neighbour stays — got \(store.state.batches.count)"
        )
        #expect(
            store.state.batches.first?.persistedID == 5,
            "and what is left is the batch that was already there"
        )
    }
}
