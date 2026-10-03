//
//  TestSupport.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 29.09.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// A `CalendarPersisting` that keeps the batch graph in memory, in domain types.
///
/// The real adapter (`CalendarStore`) lives in the app target, not in a package, so a
/// package test cannot use it — and it should not: mapping `EventBatchDataSource` to
/// `CalendarEventBatch` is the composition root's job, and the feature layer is only
/// allowed to see the domain side of it. So this fake implements the port directly, which
/// is also what proves the port is narrow enough to implement without the DTOs in scope.
///
/// Ids are assigned on write, the way the real store does, because §6.5 adoption depends
/// on a committed batch coming back with a real `persistedID`.
actor InMemoryCalendarPersisting: CalendarPersisting {
    private var calendar: PinCalendar?
    private var batches: [Int64: [CalendarEventBatch]] = [:]
    private var nextID: Int64 = 1

    private(set) var writes: [(calendarID: Int64, columns: Int, batches: [CalendarEventBatch])] = []

    init(calendar: PinCalendar? = nil, initialBatches: [CalendarEventBatch] = []) {
        self.calendar = calendar
        if let calendar {
            batches[calendar.id] = initialBatches
        }
    }

    func calendar(id: Int64) async throws -> PinCalendar? {
        calendar?.id == id ? calendar : nil
    }

    /// Changes the stored calendar's metadata, or removes it with `nil`.
    ///
    /// A test that exercises the change feed has to do this *and* publish. The two fakes are
    /// separate objects, and that is the honest shape — a write goes through the persisting
    /// port and the announcement comes from the managing one. Announcing without writing
    /// would leave the model re-fetching the old value and failing for a reason that has
    /// nothing to do with the feed.
    func update(_ calendar: PinCalendar?) {
        self.calendar = calendar
    }

    func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch] {
        batches[calendarID] ?? []
    }

    func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws {
        let assigned = eventBatches.map { batch -> CalendarEventBatch in
            guard batch.persistedID == nil else { return batch }
            let assignedID = nextID
            nextID += 1
            return batch.with(persistedID: assignedID)
        }
        batches[id] = assigned
        writes.append((id, numberOfColumns, assigned))
    }

    /// The rows as they now stand, for asserting what a save actually did.
    func storedBatches(calendarID: Int64) -> [CalendarEventBatch] {
        batches[calendarID] ?? []
    }

    /// Waits until `expected` writes have landed, or the deadline passes.
    ///
    /// A fixed sleep is the wrong tool: the store drains its write chain on the scheduler,
    /// so how long that takes depends on the machine, and a busy one can still be
    /// mid-chain when a sleep expires — which reads as "writes were lost" rather than "the
    /// test gave up waiting". Polling for the condition tells those two apart.
    @discardableResult
    func waitForWrites(_ expected: Int, timeout: Duration = .seconds(5)) async -> Int {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if writes.count >= expected { return writes.count }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return writes.count
    }

    /// Waits until the *most recent* write satisfies `predicate`, and hands it back.
    ///
    /// The counterpart to `waitForWrites`, for when the interesting thing is the content of the
    /// final write rather than how many there were.
    ///
    /// It has to be this and not `waitForWrites(1)` plus `writes.last`. An edit that persists as
    /// it is made enqueues one write per edit, all serialised down the same chain, so a test that
    /// waits for the first of three reads whichever landed first and concludes the *last* one was
    /// wrong. That is a flake whose failure names the feature under test rather than the harness,
    /// which is the worst kind: it reads as §16 regressing when the assertion simply ran too early.
    ///
    /// Polling for the condition is the same discipline as above, one predicate wider.
    @discardableResult
    func waitForLastWrite(
        timeout: Duration = .seconds(5),
        where predicate: @Sendable ([CalendarEventBatch]) -> Bool
    ) async -> [CalendarEventBatch]? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let last = writes.last, predicate(last.batches) { return last.batches }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return writes.last?.batches
    }
}

/// A `CalendarManaging` that keeps one calendar in memory and lets a test publish changes.
///
/// The counterpart to `InMemoryCalendarPersisting`, and needed for the same reason: the real
/// implementation lives in the app target. `SingleCalendarModel` follows calendar
/// *metadata* through this port, so a test that wants to see it react has to be able to
/// publish a change — and has to be able to await the subscription being live, which is
/// exactly the trap §4b.1 records about a push stream having no replay.
actor InMemoryCalendarManaging: CalendarManaging {
    private var calendar: PinCalendar
    /// A fresh `AsyncStream` per subscriber, as the real port hands out.
    private var continuations: [UUID: AsyncStream<PinCalendarChange>.Continuation] = [:]

    private(set) var subscriberCount = 0

    init(calendar: PinCalendar) {
        self.calendar = calendar
    }

    /// Publishes a change and applies it to the matching persisting fake.
    ///
    /// One call, because the two have to agree: the write lands through
    /// `CalendarPersisting` and the announcement comes from `CalendarManaging`, so a test
    /// that only does one of them is testing a world where the announcement is a lie.
    @discardableResult
    func publish(
        _ change: PinCalendarChange,
        onto persistence: InMemoryCalendarPersisting? = nil,
        timeout: Duration = .seconds(5)
    ) async -> Int {
        switch change {
        case .added(let calendar), .changed(let calendar):
            self.calendar = calendar
            await persistence?.update(calendar)
        case .removed:
            // The model only goes `.empty` if the read now finds nothing, so a removal has
            // to remove the row rather than rewrite it.
            await persistence?.update(nil)
        case .refreshed(let calendars):
            await persistence?.update(calendars.first ?? calendar)
        }
        await waitForSubscribers(timeout: timeout)
        for continuation in continuations.values {
            continuation.yield(change)
        }
        return continuations.count
    }

    /// Blocks until at least one subscriber is registered.
    @discardableResult
    func waitForSubscribers(timeout: Duration = .seconds(5)) async -> Int {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !continuations.isEmpty { return continuations.count }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return continuations.count
    }

    /// `nonisolated`, as the protocol declares it. The registration is a `makeStream`
    /// followed by an actor hop rather than a mutation inside the builder closure, which
    /// cannot touch isolated state at all.
    nonisolated func changes() async -> AsyncStream<PinCalendarChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PinCalendarChange>.makeStream()
        await subscribe(id: id, continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id: id) }
        }
        return stream
    }

    private func subscribe(
        id: UUID,
        continuation: AsyncStream<PinCalendarChange>.Continuation
    ) {
        continuations[id] = continuation
        subscriberCount = continuations.count
    }

    private func unsubscribe(id: UUID) {
        continuations[id] = nil
        subscriberCount = continuations.count
    }

    // The remaining operations are not what this fake exists for; a test that starts
    // driving them belongs in the list's suite, which has its own fake.
    func loadActive() async -> [PinCalendar] { [calendar] }
    func loadArchived() async -> [PinCalendar] { calendar.isArchived ? [calendar] : [] }
    func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws {}
    func updateCalendar(_ calendar: PinCalendar) async throws { self.calendar = calendar }
    func archiveCalendar(id: Int64) async throws {}
    func restoreCalendar(id: Int64) async throws {}
    func permanentlyDeleteCalendar(id: Int64) async throws {}
}

@MainActor
enum Fixture {

    static func day(_ dayOfMonth: Int, month: Int = 6, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        return calendar.date(from: components)!
    }

    static func event(
        _ name: String,
        on dayOfMonth: Int,
        color: String = "eventColorOption1",
        persistedID: Int64? = nil
    ) -> CalendarEvent {
        CalendarEvent(persistedID: persistedID, name: name, date: day(dayOfMonth), colorName: color)
    }

    static func batch(
        _ name: String,
        on dayOfMonth: Int,
        id: Int64? = nil,
        color: String = "eventColorOption1"
    ) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: id,
            name: name,
            colorName: color,
            events: [event("Event", on: dayOfMonth, color: color)]
        )
    }

    /// A store opened on `calendarID` with `batches` already synced.
    ///
    /// `perform` refuses to write against calendar 0, so a store that has never synced
    /// cannot be asked to persist anything — a store under test is always a store that
    /// knows which calendar it is.
    static func makeStore(
        calendarID: Int64 = 42,
        batches: [CalendarEventBatch] = [],
        persistence: InMemoryCalendarPersisting,
        columnCountResolver: @escaping (Int) -> Int = { $0 }
    ) -> PCEventSelectionManager {
        let store = PCEventSelectionManager(
            initialState: PCEventSelectionState(dataProvider: PCCalendarDataProvider()),
            persistence: persistence,
            daySelectionManager: PCCalendarDaySelectionManager(),
            columnCountResolver: columnCountResolver
        )
        store.send(.syncCalendar(calendarID: calendarID, batches: batches))
        return store
    }

    /// A main-calendar model wired to `store`, over in-memory ports.
    ///
    /// `managing` defaults to a feed for `calendarID` that nothing publishes on, for the
    /// suites that are about the batch graph and have no reason to drive calendar metadata.
    /// Anything asserting that the model *follows* metadata must pass its own fake and use
    /// `waitForSubscribers` — see the trap §4b.1 records about a push stream having no replay.
    static func makeModel(
        calendarID: Int64 = 42,
        store: PCEventSelectionManager,
        persistence: InMemoryCalendarPersisting,
        managing: InMemoryCalendarManaging? = nil,
        columnCountResolver: @escaping (Int) -> Int = { $0 }
    ) -> SingleCalendarModel {
        let managing = managing ?? InMemoryCalendarManaging(
            calendar: PinCalendar(id: calendarID, name: "Test", year: 2026, numberOfColumns: 3)
        )
        return SingleCalendarModel(
            calendarid: calendarID,
            managing: managing,
            persistence: persistence,
            store: store,
            columnCountResolver: columnCountResolver
        )
    }
}
