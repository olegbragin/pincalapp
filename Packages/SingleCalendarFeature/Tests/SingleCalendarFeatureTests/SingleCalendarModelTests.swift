//
//  SingleCalendarModelTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 04.02.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// The model, the store it dispatches to, and the management port that feeds it metadata.
///
/// Built over two domain fakes and no `CorePersistence` at all, which is the point: the
/// model reached a `CalendarCache` for exactly one thing — its metadata change feed — and
/// dropping that removed the package's last dependency on the storage vocabulary.
@MainActor
private func makeFixture(
    calendar: PinCalendar
) -> (
    InMemoryCalendarPersisting,
    InMemoryCalendarManaging,
    PCEventSelectionManager,
    SingleCalendarModel
) {
    let persistence = InMemoryCalendarPersisting(calendar: calendar)
    let managing = InMemoryCalendarManaging(calendar: calendar)
    let store = PCEventSelectionManager(
        initialState: PCEventSelectionState(dataProvider: PCCalendarDataProvider()),
        persistence: persistence,
        daySelectionManager: PCCalendarDaySelectionManager()
    )
    let model = SingleCalendarModel(
        calendarid: calendar.id,
        managing: managing,
        persistence: persistence,
        store: store
    )
    return (persistence, managing, store, model)
}

@MainActor
private func makeCalendar(
    id: Int64 = 42,
    name: String = "Calendar",
    year: Int = 2026,
    archived: Bool = false
) -> PinCalendar {
    PinCalendar(
        id: id,
        name: name,
        year: year,
        numberOfColumns: 3,
        isArchived: archived
    )
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 10,
    _ condition: () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while await !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// The main calendar panel.
///
/// This suite is now deliberately narrow. It used to test `route(for:)`,
/// `prepareAddEditEventBatchViewModel`, `commitPendingBatch`, `deleteBatches`,
/// `cancelMultipleChanges` and `save(for:)` — all of which moved into the reducer and the
/// store, where `PCEventSelectionReducerTests` and `PCEventSelectionManagerTests` cover
/// them directly and without a database in the way. What is left here is what this object
/// still owns: loading a calendar, projecting markers onto the main matrix, and dispatching.
@MainActor
@Suite("SingleCalendarModel Tests")
struct SingleCalendarModelTests {
    @Test("Initial state is empty with no content")
    func initialStateIsEmpty() {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar())
        #expect(model.state == .empty)
        #expect(model.label.isEmpty)
    }

    @Test("fetch loads the calendar and builds the year model")
    func fetchBuildsYearModel() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar(year: 2026))
        await model.fetch(force: true)

        #expect(model.state == .content)
        #expect(model.label == "Calendar")
        #expect(model.yearModel.year == 2026)
        #expect(!model.yearModel.months.isEmpty)
    }

    @Test("fetch without force does not reload existing content")
    func fetchWithoutForceIsSkipped() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar(name: "Original"))
        await model.fetch(force: true)
        #expect(model.label == "Original")

        await model.fetch()
        #expect(model.label == "Original")
    }

    @Test("fetch reloads after a metadata change is published")
    func fetchReloadsFromManaging() async {
        let (persistence, managing, _, model) = makeFixture(calendar: makeCalendar(name: "Original"))
        await model.fetch(force: true)
        #expect(model.label == "Original")

        // The feed, not a read. This is the path that needed the cache: a push stream has
        // no replay, so a change published before the model's `for await` is live is simply
        // dropped. `publish` applies the write to the persisting fake *and* waits for the
        // subscriber, so the announcement and the data cannot disagree.
        await managing.publish(.changed(makeCalendar(name: "Renamed")), onto: persistence)

        await waitUntil { model.label == "Renamed" }

        #expect(model.label == "Renamed")
    }

    @Test("A metadata change about a different calendar is ignored")
    func ignoresOtherCalendarsChanges() async {
        let (_, managing, _, model) = makeFixture(calendar: makeCalendar(id: 42, name: "Mine"))
        await model.fetch(force: true)

        await managing.publish(
            .changed(makeCalendar(id: 7, name: "Theirs")),
            onto: InMemoryCalendarPersisting(calendar: makeCalendar(id: 7, name: "Theirs"))
        )
        // Long enough for a wrongly-delivered change to have arrived and re-fetched.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(model.label == "Mine", "a change to another calendar must not rename this one")
    }

    @Test("A removed calendar empties the panel rather than leaving a stale one")
    func removedCalendarGoesEmpty() async {
        let (persistence, managing, _, model) = makeFixture(calendar: makeCalendar(name: "Doomed"))
        await model.fetch(force: true)
        #expect(model.state == .content)

        await managing.publish(.removed(makeCalendar(name: "Doomed")), onto: persistence)

        await waitUntil { model.state == .empty }
        #expect(model.state == .empty)
    }

    @Test("fetch marks the state empty when the calendar is missing")
    func fetchMissingCalendar() async {
        // The model reads its metadata through `CalendarPersisting`, so the calendar has to
        // be absent *there*. A fixture that seeded it would answer the read and leave the
        // model legitimately `.content` — which is a different test.
        let model = SingleCalendarModel(
            calendarid: 99,
            managing: InMemoryCalendarManaging(calendar: makeCalendar(id: 99)),
            persistence: InMemoryCalendarPersisting(calendar: nil),
            store: PCEventSelectionManager(
                initialState: PCEventSelectionState(dataProvider: PCCalendarDataProvider()),
                persistence: InMemoryCalendarPersisting(calendar: nil),
                daySelectionManager: PCCalendarDaySelectionManager()
            )
        )
        await model.fetch(force: true)

        #expect(model.state == .empty)
    }

    @Test("An archived calendar is reported as archived")
    func reportsArchived() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar(archived: true))
        await model.fetch(force: true)
        #expect(model.isArchived)
    }

    @Test("fetch hands the store the calendar's batches")
    func fetchSyncsTheStore() async {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        #expect(store.state.calendarID == 42, "the store now knows which calendar it is")
    }

    @Test("hasEvents reads the store's registry")
    func hasEventsReadsTheStore() {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        let day = Fixture.day(4)
        #expect(!model.hasEvents(on: day))

        store.send(.syncCalendar(calendarID: 42, batches: [Fixture.batch("Morning", on: 4, id: 1)]))

        #expect(model.hasEvents(on: day))
        #expect(!model.hasEvents(on: Fixture.day(5)))
    }

    // MARK: - Multi-select session, projected

    @Test("The multi-select session is off until it is turned on")
    func multiSelectDefaultsOff() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        #expect(!model.isMultiSelectMode)
        #expect(model.selectedColor == nil)
        #expect(!model.isColorPickerDisabled)
    }

    @Test("Turning multi-select on and off is dispatched to the store")
    func multiSelectDispatch() async {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.setMultiSelectMode(true)
        #expect(model.isMultiSelectMode)
        #expect(store.state.multiSelectMode)

        model.setMultiSelectMode(false)
        #expect(!model.isMultiSelectMode)
        #expect(!store.state.multiSelectMode)
    }

    @Test("The colour binding dispatches into the store's session")
    func multiSelectColorBinding() async {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.multiSelectColorBinding.wrappedValue = .option3

        #expect(store.state.multiSelectColor == .option3)
        #expect(model.selectedColor == .option3)
    }

    @Test("The picker is disabled once days and a colour are chosen")
    func pickerDisabledOnceSeeded() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.setMultiSelectMode(true)
        #expect(!model.isColorPickerDisabled, "no days yet")

        model.multiSelectColorBinding.wrappedValue = .option1
        #expect(!model.isColorPickerDisabled, "still no days")

        model.send(.dayTappedInCalendar(Fixture.day(4)))
        #expect(model.isColorPickerDisabled)
    }

    @Test("Cancelling multi-select empties the session")
    func cancelMultiSelect() async {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)
        model.setMultiSelectMode(true)
        model.setMultiSelectColor(.option1)
        model.send(.dayTappedInCalendar(Fixture.day(4)))

        model.cancelMultiSelect()

        #expect(!store.state.multiSelectMode)
        #expect(store.state.multiSelectDays.isEmpty)
        #expect(store.state.multiSelectColor == nil)
    }

    // MARK: - Year matrix

    @Test("Switching year rebuilds the month matrix")
    func switchYearRebuilds() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar(year: 2026))
        await model.fetch(force: true)
        #expect(model.yearModel.year == 2026)

        model.switchYear(to: 2027)
        #expect(model.yearModel.year == 2027)

        model.switchYear(to: 2027)
        #expect(model.yearModel.year == 2027, "switching to the same year is a no-op")
    }

    @Test("Changing the column count is dispatched, so the store persists it")
    func columnCountDispatch() async {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.setNumberOfColumns(2)

        #expect(store.state.numberOfColumns == 2)
    }

    @Test("Markers from the store appear on the main matrix")
    func markersAreProjected() async {
        let (_, _, store, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        store.send(.syncCalendar(calendarID: 42, batches: [Fixture.batch("Morning", on: 4, color: "eventColorOption3")]))
        model.send(.ensureAssemblyStarted) // any dispatch re-projects

        let marked = model.yearModel.months
            .flatMap(\.weeks)
            .flatMap(\.days)
            .filter { !$0.events.isEmpty }
        #expect(marked.count == 1, "one day carries a marker")
        #expect(marked.first?.events == ["eventColorOption3"])
    }

    @Test("reset clears loaded content")
    func resetClearsContent() async {
        let (_, _, _, model) = makeFixture(calendar: makeCalendar(name: "Original"))
        await model.fetch(force: true)

        model.reset()

        #expect(model.state == .empty)
        #expect(model.label.isEmpty)
    }
}
