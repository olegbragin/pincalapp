import Foundation
import Testing
import CorePersistence
import DSKit
import CoreDomain
import AppNavigation
@testable import SingleCalendarFeature

final class InMemoryCalendarRepository: CalendarRepository, @unchecked Sendable {
    private var calendars: [Int64: CalendarDataSource] = [:]
    private var nextID: Int64 = 1

    init(seed: [CalendarDataSource] = []) {
        for calendar in seed {
            calendars[calendar.id] = calendar
            if calendar.id >= nextID {
                nextID = calendar.id + 1
            }
        }
    }

    func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        calendars[id]
    }

    @discardableResult
    func saveCalendar(_ calendar: CalendarDataSource) async throws -> Int64 {
        var stored = calendar
        if stored.id == 0 {
            stored.id = nextID
            nextID += 1
        }
        calendars[stored.id] = stored
        return stored.id
    }

    @discardableResult
    func deleteCalendar(_ calendarId: Int64) async throws -> Int64 {
        calendars.removeValue(forKey: calendarId)
        return calendarId
    }

    func getAllCalendars() async throws -> [CalendarDataSource] {
        calendars.values.sorted { $0.id < $1.id }
    }

    func getActiveCalendars() async throws -> [CalendarDataSource] {
        calendars.values.filter { !$0.isArchived }.sorted { $0.id < $1.id }
    }

    func getArchivedCalendars() async throws -> [CalendarDataSource] {
        calendars.values.filter { $0.isArchived }.sorted { $0.id < $1.id }
    }

    func archiveCalendar(_ calendarId: Int64) async throws {
        guard var calendar = calendars[calendarId] else { return }
        calendar.isArchived = true
        calendars[calendarId] = calendar
    }

    func restoreCalendar(_ calendarId: Int64) async throws {
        guard var calendar = calendars[calendarId] else { return }
        calendar.isArchived = false
        calendars[calendarId] = calendar
    }

    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws {}

    func renameCalendar(_ id: Int64, to name: String) {
        guard var calendar = calendars[id] else { return }
        calendar.name = name
        calendars[id] = calendar
    }
}

@MainActor
private func makeCalendar(
    id: Int64 = 42,
    name: String = "Test Calendar",
    year: Int = 2026,
    columns: Int = 3,
    isArchived: Bool = false,
    eventBatches: [EventBatchDataSource] = []
) -> CalendarDataSource {
    CalendarDataSource(
        id: id,
        name: name,
        year: year,
        numberOfColumns: columns,
        isArchived: isArchived,
        eventBatches: eventBatches
    )
}

@MainActor
private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

@MainActor
private func event(_ name: String, on date: Date, color: String = "eventColorOption1") -> EventDataSource {
    EventDataSource(name: name, date: date, color: color)
}

@MainActor
private func makeFixture(calendar: CalendarDataSource) -> (InMemoryCalendarRepository, CalendarCache, SingleCalendarModel) {
    let repository = InMemoryCalendarRepository(seed: [calendar])
    let cache = CalendarCache(repository: repository)
    let model = SingleCalendarModel(calendarid: calendar.id, cache: cache)
    return (repository, cache, model)
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

@MainActor
@Suite("SingleCalendarModel Tests")
struct SingleCalendarModelTests {

    @MainActor
    private func makeBatchEditor(for model: SingleCalendarModel) -> AddEditEventBatchViewModel {
        model.makeBatchEditor()
    }

    @Test("Initial state is empty with no content")
    func initialState() {
        let (_, _, model) = makeFixture(calendar: makeCalendar())

        #expect(model.state == .empty)
        #expect(model.label == "")
        #expect(model.calendarid == 42)
        #expect(model.isArchived == false)
        #expect(model.yearModel.months.isEmpty)
    }

    @Test("fetch loads calendar and builds the year model")
    func fetchPopulatesContent() async throws {
        let (_, _, model) = makeFixture(calendar: makeCalendar(name: "My Calendar", year: 2026))

        await model.fetch(force: true)

        #expect(model.state == .content)
        #expect(model.label == "My Calendar")
        #expect(model.isArchived == false)
        #expect(model.yearModel.months.count == 12)
        #expect(model.yearModel.numberOfCurrentMonth > 0)
    }

    @Test("fetch without force does not reload existing content")
    func fetchUsesCachedContent() async throws {
        let (repository, _, model) = makeFixture(calendar: makeCalendar(name: "Original", year: 2026))
        await model.fetch(force: true)
        #expect(model.label == "Original")

        // A change made directly to the repository bypasses the cache, which is
        // the single source of truth. fetch therefore does not observe it.
        repository.renameCalendar(42, to: "Renamed")

        await model.fetch()
        #expect(model.label == "Original")

        await model.fetch(force: true)
        #expect(model.label == "Original")
    }

    @Test("fetch reloads from the cache after a cache update")
    func fetchReloadsFromCacheAfterUpdate() async throws {
        let (_, cache, model) = makeFixture(calendar: makeCalendar(name: "Original", year: 2026))
        await model.fetch(force: true)
        #expect(model.label == "Original")

        let renamed = CalendarDataSource(id: 42, name: "Renamed", year: 2026, numberOfColumns: 3)
        try await cache.updateCalendar(renamed)
        await waitUntil { model.label == "Renamed" }
        #expect(model.label == "Renamed")
    }

    @Test("fetch marks state empty when calendar is missing")
    func fetchMissingCalendar() async throws {
        let repository = InMemoryCalendarRepository()
        let cache = CalendarCache(repository: repository)
        let model = SingleCalendarModel(calendarid: 99, cache: cache)

        await model.fetch(force: true)

        #expect(model.state == .empty)
    }

    @Test("hasEvents reflects batch events and batch-level dates")
    func hasEventsOnDate() async throws {
        let eventDay = day(2026, 6, 1)
        let batch = EventBatchDataSource(
            id: 7,
            name: "Vacation",
            colorName: "eventColorOption2",
            events: [event("Trip", on: eventDay)]
        )
        let (_, _, model) = makeFixture(calendar: makeCalendar(eventBatches: [batch]))
        await model.fetch(force: true)

        #expect(model.hasEvents(on: eventDay))
        #expect(!model.hasEvents(on: day(2026, 6, 2)))

        let dateBatch = EventBatchDataSource(id: 8, name: "Whole day", date: day(2026, 6, 3))
        let (_, _, model2) = makeFixture(calendar: makeCalendar(id: 43, eventBatches: [dateBatch]))
        await model2.fetch(force: true)

        #expect(model2.hasEvents(on: day(2026, 6, 3)))
    }

    @Test("route returns nil without a selected day")
    func routeNilWithoutSelection() {
        let (_, _, model) = makeFixture(calendar: makeCalendar())

        #expect(model.route(for: []) == nil)
    }

    @Test("route returns nil for an archived calendar")
    func routeNilWhenArchived() async throws {
        let (_, _, model) = makeFixture(calendar: makeCalendar(isArchived: true))
        await model.fetch(force: true)

        #expect(model.route(for: [day(2026, 6, 1)]) == nil)
    }

    @Test("route opens day batches when the selected day has events")
    func routeToDayBatches() async throws {
        let eventDay = day(2026, 6, 1)
        let batch = EventBatchDataSource(id: 1, name: "Events", events: [event("A", on: eventDay)])
        let (_, _, model) = makeFixture(calendar: makeCalendar(eventBatches: [batch]))
        await model.fetch(force: true)

        let route = model.route(for: [eventDay])

        #expect(route == .dayBatches(eventDay))
    }

    @Test("route opens batch editor for a new day without events")
    func routeToBatchEditor() async throws {
        let (_, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        let newDay = day(2026, 6, 1)
        let route = model.route(for: [newDay])

        #expect(route == .batchEditor(.newDay(newDay)))
    }

    @Test("route in multiple mode with a color toggles a tinted event and returns nil")
    func routeMultipleModeTogglesEvent() async throws {
        let someDay = day(2026, 6, 1)
        let (_, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.daySelectionManager.selectionMode = .multiple
        model.selectedColor = .option1

        #expect(model.route(for: [someDay]) == nil)
        #expect(model.isColorPickerDisabled == true)
        #expect(model.selectedEvents.isEmpty)

        _ = model.route(for: [someDay])

        #expect(model.isColorPickerDisabled == false)

        model.cancelMultipleChanges()
        #expect(model.isColorPickerDisabled == false)
    }

    @Test("color picker becomes disabled after adding an event in multiple mode")
    func colorPickerDisabledInMultipleMode() async throws {
        let someDay = day(2026, 6, 1)
        let (_, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        #expect(model.isColorPickerDisabled == false)

        model.daySelectionManager.selectionMode = .multiple
        model.selectedColor = .option1
        _ = model.route(for: [someDay])

        #expect(model.isColorPickerDisabled == true)

        model.cancelMultipleChanges()
        #expect(model.isColorPickerDisabled == false)
    }

    @Test("prepareAddEditEventBatchViewModel seeds the editor state")
    func prepareAddEditEventBatchViewModelForDate() async throws {
        let someDay = day(2026, 6, 1)
        let (_, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.prepareNewBatchEvents(on: someDay)
        let batchModel = makeBatchEditor(for: model)
        batchModel.load(nil, selectedDay: someDay)
        #expect(batchModel.eventBatchId == 0)
        #expect(batchModel.eventBatchName == "")
        #expect(batchModel.selectedColor == .option1)
        #expect(batchModel.date == someDay)
        #expect(batchModel.eventsSelectionManager.events.count == 1)
        #expect(batchModel.eventsSelectionManager.events.first?.date == someDay)
    }

    @Test("commitPendingBatch appends a brand-new batch")
    func commitPendingBatchAppendsNew() async throws {
        let someDay = day(2026, 6, 1)
        let (_, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)
        #expect(!model.hasEvents(on: someDay))

        model.prepareNewBatchEvents(on: someDay)
        let batchModel = makeBatchEditor(for: model)
        batchModel.load(nil, selectedDay: someDay)
        batchModel.eventBatchName = "Summer"
        batchModel.selectedColor = .option1
        batchModel.eventsSelectionManager.addEvent(event("A", on: someDay))
        #expect(batchModel.save())

        model.commitPendingBatch(batchModel.eventBatch)

        #expect(model.hasEvents(on: someDay))
    }

    @Test("commitPendingBatch replaces an existing persisted batch")
    func commitPendingBatchReplacesExisting() async throws {
        let day1 = day(2026, 6, 1)
        let day2 = day(2026, 6, 2)
        let original = EventBatchDataSource(
            id: 11,
            name: "Old",
            colorName: "eventColorOption2",
            events: [event("A", on: day1)]
        )
        let (_, _, model) = makeFixture(calendar: makeCalendar(eventBatches: [original]))
        await model.fetch(force: true)
        #expect(model.hasEvents(on: day1))

        let batchModel = makeBatchEditor(for: model)
        batchModel.load(original)
        batchModel.eventsSelectionManager.removeEvent(on: day1)
        batchModel.eventsSelectionManager.addEvent(event("B", on: day2))
        #expect(batchModel.save())

        model.commitPendingBatch(batchModel.eventBatch)

        #expect(!model.hasEvents(on: day1))
        #expect(model.hasEvents(on: day2))
    }

    @Test("commitPendingBatch removes a persisted batch whose events were emptied")
    func commitPendingBatchRemovesEmpty() async throws {
        let someDay = day(2026, 6, 1)
        let original = EventBatchDataSource(
            id: 11,
            name: "Old",
            colorName: "eventColorOption2",
            events: [event("A", on: someDay)]
        )
        let (_, _, model) = makeFixture(calendar: makeCalendar(eventBatches: [original]))
        await model.fetch(force: true)
        #expect(model.hasEvents(on: someDay))

        let batchModel = makeBatchEditor(for: model)
        batchModel.load(original)
        batchModel.eventsSelectionManager.removeEvent(on: someDay)
        #expect(batchModel.save())

        model.commitPendingBatch(batchModel.eventBatch)

        #expect(!model.hasEvents(on: someDay))
    }

    @Test("deleteBatches removes the given batches and persists")
    func deleteBatchesRemoves() async throws {
        let day1 = day(2026, 6, 1)
        let day2 = day(2026, 6, 2)
        let batch1 = EventBatchDataSource(id: 1, name: "One", events: [event("A", on: day1)])
        let batch2 = EventBatchDataSource(id: 2, name: "Two", events: [event("B", on: day2)])
        let (repository, _, model) = makeFixture(calendar: makeCalendar(eventBatches: [batch1, batch2]))
        await model.fetch(force: true)

        model.deleteBatches([batch1], for: 42)

        #expect(!model.hasEvents(on: day1))
        #expect(model.hasEvents(on: day2))

        await waitUntil {
            let calendar = try? await repository.getCalendar(id: 42)
            return calendar?.eventBatches.allSatisfy { $0.id != 1 } == true
        }

        let persisted = try? await repository.getCalendar(id: 42)
        #expect(persisted?.eventBatches.contains { $0.id == 2 } == true)
        #expect(persisted?.eventBatches.allSatisfy { $0.id != 1 } == true)
    }

    @Test("reset clears loaded content")
    func resetClearsContent() async throws {
        let (_, _, model) = makeFixture(calendar: makeCalendar(name: "My Calendar"))
        await model.fetch(force: true)
        #expect(model.state == .content)

        model.reset()

        #expect(model.state == .empty)
        #expect(model.label == "")
    }

    @Test("cancelMultipleChanges reverts multi-selection edits")
    func cancelMultipleChangesReverts() async throws {
        let someDay = day(2026, 6, 1)
        let (_, _, model) = makeFixture(calendar: makeCalendar())
        await model.fetch(force: true)

        model.daySelectionManager.selectionMode = .multiple
        model.selectedColor = .option1
        _ = model.route(for: [someDay])
        #expect(model.isColorPickerDisabled)

        model.cancelMultipleChanges()

        #expect(model.daySelectionManager.selectionMode == .single)
        #expect(model.selectedColor == nil)
        #expect(!model.isColorPickerDisabled)
    }

    @Test("save persists the current number of columns")
    func savePersistsColumns() async throws {
        let (repository, _, model) = makeFixture(calendar: makeCalendar(columns: 3))
        await model.fetch(force: true)

        model.yearModel.maximumNumberOfColumns = 6
        model.yearModel.numberOfColumns = 4
        model.save(for: 42)

        await waitUntil {
            let calendar = try? await repository.getCalendar(id: 42)
            return calendar?.numberOfColumns == 4
        }

        let persisted = try? await repository.getCalendar(id: 42)
        #expect(persisted?.numberOfColumns == 4)
    }
}