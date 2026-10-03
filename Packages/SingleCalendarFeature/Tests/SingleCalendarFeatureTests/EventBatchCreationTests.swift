//
//  EventBatchCreationTests.swift
//  CorePersistenceTests
//
//  Created by Oleg Bragin on 04.08.2026.
//

import Testing
import Foundation
import ObjectBox
import DSKit
import CoreDomain
@testable import CorePersistence
@testable import SingleCalendarFeature

private struct NoopCalendarRepository: CalendarRepository {
    func getCalendar(id: Int64) async throws -> CalendarDataSource? { nil }
    @discardableResult
    func saveCalendar(_ calendar: CalendarDataSource) async throws -> Int64 { 0 }
    @discardableResult
    func deleteCalendar(_ calendarId: Int64) async throws -> Int64 { calendarId }
    func getAllCalendars() async throws -> [CalendarDataSource] { [] }
    func getActiveCalendars() async throws -> [CalendarDataSource] { [] }
    func getArchivedCalendars() async throws -> [CalendarDataSource] { [] }
    func archiveCalendar(_ calendarId: Int64) async throws {}
    func restoreCalendar(_ calendarId: Int64) async throws {}
    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws {}
}

@MainActor
struct EventBatchCreationTests {
    
    // MARK: - Helpers
    
    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
    
    private func event(_ name: String = "Event1", day: Int, color: String = "eventColorOption1", timestamp: UUID? = nil) -> EventDataSource {
        .init(name: name, date: date(year: 2026, month: 6, day: day), color: color, timestamp: timestamp)
    }
    
    private func waitForBatchCount(_ expected: Int, in store: Store, timeout: TimeInterval = 10) async throws -> Bool {
        let batchBox = store.box(for: PPEventBatch.self)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try batchBox.all().count >= expected { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try batchBox.all().count >= expected
    }
    
    // MARK: - The event list, projected from the store

    // These four used to test `prepare(with:)` and `apply(with:)` on the list view model.
    // Neither method survives: staging is `PCEventBatchAssembleUnitOfWork.new` and applying an edited
    // event is `persistEventDraft` in the reducer, both already covered there.
    // What the tests were really guarding is kept, because it is still a live invariant —
    // a batch with two events sharing a `pendingID` could not be told apart.
    @MainActor
    @Test func theAssemblyMintsUniqueIDsAndSortsByDate() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        store.send(.startNewBatch(on: Fixture.day(15)))
        store.send(.toggleDay(Fixture.day(3)))

        let events = store.state.assembly!.batch.events
        #expect(events.count == 2)
        // Placeholders carry the default name (§5.4) — the user names the batch, not each
        // day, and the name only has to be distinct enough to tell the rows apart, which
        // is what `pendingID` is for.
        #expect(events.map(\.name) == [PCEventBatchAssembleUnitOfWork.defaultEventName, PCEventBatchAssembleUnitOfWork.defaultEventName])
        #expect(
            Set(events.map(\.pendingID)).count == 2,
            "two events must not share an id, or they cannot be told apart"
        )
        #expect(events.map(\.date) == events.map(\.date).sorted(), "sorted by day")
    }

    @MainActor
    @Test func editingAnEventRewritesItInPlaceRatherThanAppending() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        store.send(.startNewBatch(on: Fixture.day(3)))
        store.send(.toggleDay(Fixture.day(4)))
        let target = store.state.assembly!.batch.events[0]

        store.send(.openEvent(pendingID: target.pendingID))
        store.send(.setEventName("Swim"))
        store.send(.setEventColor(.option3))

        let events = store.state.assembly!.batch.events
        #expect(
            store.state.stage != .idle,
            "still in the event editor: the batch was rewritten by the keystroke, not by leaving"
        )
        #expect(events.count == 2, "edited, not appended")
        #expect(
            events.filter { $0.colorName == "eventColorOption3" }.count == 1,
            "exactly the edited event changed colour"
        )
        #expect(
            events.filter { $0.colorName == store.state.assembly!.batch.colorName }.count == 1,
            "and the other placeholder still wears the batch's colour, untouched"
        )
    }

    // MARK: - AddEditEventBatchViewModel

    // The nine tests that used to live here drove the view model through its settable
    // `eventBatchName` / `selectedColor` fields and read back a stored `eventBatch` DTO.
    // None of that exists: the view model is a projection facade with commands that
    // dispatch, and the batch is `state.assembly`. Every scenario they covered — canSave
    // requiring a name and a colour, save failing without either, the default colour
    // falling back to the first event's, recolouring propagating to every event, reset
    // clearing the batch — is now in `AddEditEventBatchViewModelTests`, asserted against
    // the store rather than against local fields.

    // MARK: - SingleCalendarModel, and the batch screen's calendar

    // The twelve tests from here to the end drove `SingleCalendarModel.changeEvent`,
    // `prepareAddEditEventBatchViewModel`, `commitPendingBatch`, `route(for:)` and
    // `AddEditEventBatchViewModel.toggleEvent` — every one of them a method this stage
    // removed, because the behaviour they describe is now `PCEventSelectionState` and the
    // reducer that owns it.
    //
    // Nothing is lost. The picker-disabled states are in `SingleCalendarModelTests`
    // (`pickerDisabledOnceSeeded`, `multiSelectDefaultsOff`); the day-toggling on the
    // batch screen is `AddEditEventBatchViewModelTests` plus `toggleDay` in
    // `PCEventSelectionReducerTests`; and the commit-and-persist paths are in
    // `SingleCalendarModelObjectBoxIntegrationTests`. Keeping copies here would have meant
    // keeping a second, DTO-shaped description of the same rules, which is the thing the
    // stage exists to delete.
}
