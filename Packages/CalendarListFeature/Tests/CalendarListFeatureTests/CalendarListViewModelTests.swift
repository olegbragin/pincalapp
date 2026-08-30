import Testing
import Foundation
import CorePersistence

@testable import CalendarListFeature

// MARK: - In-memory CalendarRepository for Testing

/// In-memory implementation of `CalendarRepository` so tests can exercise the
/// real `CalendarCache` (actor) without touching ObjectBox.
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

    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws {
        // Not exercised by these tests.
    }
}

// MARK: - Helpers

@MainActor
private func makeFixture(seed: [CalendarDataSource] = []) -> (CalendarCache, CalendarListViewModel) {
    let repository = InMemoryCalendarRepository(seed: seed)
    let cache = CalendarCache(repository: repository)
    let vm = CalendarListViewModel(mode: .active, cache: cache)
    return (cache, vm)
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

// MARK: - CalendarListViewModel Tests

@MainActor
@Suite("CalendarListViewModel Tests")
struct CalendarListViewModelTests {

    @Test("Initial state has empty calendars and loading true")
    func initialState() {
        let (_, vm) = makeFixture()

        #expect(vm.calendars.isEmpty)
        #expect(vm.isLoading == true)
        #expect(vm.displayMode == .list)
        #expect(vm.mode == .active)
    }

    @Test("Archived mode initializes with archived mode")
    func archivedMode() {
        let repository = InMemoryCalendarRepository()
        let cache = CalendarCache(repository: repository)
        let vm = CalendarListViewModel(mode: .archived, cache: cache)

        #expect(vm.mode == .archived)
    }

    @Test("DisplayMode toggles between list and grid")
    func displayModeToggle() {
        #expect(DisplayMode.list.toggled == .grid)
        #expect(DisplayMode.grid.toggled == .list)
    }

    @Test("DisplayMode has correct icons and labels")
    func displayModeIconsAndLabels() {
        #expect(DisplayMode.list.icon == "rectangle.grid.1x2")
        #expect(DisplayMode.list.label == "List")
        #expect(DisplayMode.grid.icon == "rectangle.grid.2x2")
        #expect(DisplayMode.grid.label == "Grid")
    }

    @Test("addItem resets addEditCalendarViewModel")
    func addItem() {
        let (_, vm) = makeFixture()
        vm.addEditCalendarViewModel.id = 42
        vm.addEditCalendarViewModel.label = "Test"
        vm.addEditCalendarViewModel.calendar = CalendarDataSource(id: 7, name: "Existing", year: 2026, numberOfColumns: 3)

        vm.addItem()

        #expect(vm.addEditCalendarViewModel.id == 0)
        #expect(vm.addEditCalendarViewModel.label == "")
        #expect(vm.addEditCalendarViewModel.calendar == nil)
    }
}

// MARK: - AddEditCalendarViewModel Tests

@Suite("AddEditCalendarViewModel Tests")
struct AddEditCalendarViewModelTests {

    @Test("AddEditCalendarViewModel saves valid label")
    func addEditCalendarViewModelSaveValid() {
        let vm = AddEditCalendarViewModel()
        vm.label = "Test Calendar"

        let result = vm.save()

        #expect(result == true)
        #expect(vm.calendar != nil)
        #expect(vm.calendar?.name == "Test Calendar")
    }

    @Test("AddEditCalendarViewModel fails to save empty label")
    func addEditCalendarViewModelSaveEmpty() {
        let vm = AddEditCalendarViewModel()
        vm.label = ""

        let result = vm.save()

        #expect(result == false)
        #expect(vm.calendar == nil)
    }

    @Test("AddEditCalendarViewModel reset clears state")
    func addEditCalendarViewModelReset() {
        let vm = AddEditCalendarViewModel()
        vm.id = 42
        vm.label = "Test"
        vm.calendar = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3)

        vm.reset()

        #expect(vm.id == 0)
        #expect(vm.label == "")
        #expect(vm.calendar == nil)
    }
}

// MARK: - CalendarDataSource Tests

@Suite("CalendarDataSource Tests")
struct CalendarDataSourceTests {

    @Test("CalendarDataSource is identifiable and hashable")
    func calendarDataSourceHashable() {
        let cal1 = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let cal2 = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let cal3 = CalendarDataSource(id: 2, name: "Other", year: 2026, numberOfColumns: 2)

        #expect(cal1 == cal2)
        #expect(cal1 != cal3)
        #expect(cal1.hashValue == cal2.hashValue)
    }

    @Test("CalendarDataSource isArchived defaults to false")
    func calendarDataSourceDefaultArchived() {
        let cal = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3)

        #expect(cal.isArchived == false)
    }

    @Test("CalendarDataSource can be created with isArchived")
    func calendarDataSourceWithArchived() {
        let cal = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3, isArchived: true)

        #expect(cal.isArchived == true)
    }
}

// MARK: - CalendarListMode Tests

@Suite("CalendarListMode Tests")
struct CalendarListModeTests {

    @Test("CalendarListMode has active and archived cases")
    func calendarListModeCases() {
        let active = CalendarListMode.active
        let archived = CalendarListMode.archived

        #expect(active == .active)
        #expect(archived == .archived)
        #expect(active != archived)
    }
}

// MARK: - Integration Tests with In-Memory Repository

@MainActor
@Suite("CalendarListViewModel Integration Tests")
struct CalendarListViewModelIntegrationTests {

    @Test("fetch loads active calendars")
    func fetchActiveCalendars() async {
        let repository = InMemoryCalendarRepository(seed: [
            CalendarDataSource(id: 1, name: "Calendar 1", year: 2026, numberOfColumns: 3),
            CalendarDataSource(id: 2, name: "Calendar 2", year: 2026, numberOfColumns: 2)
        ])
        let cache = CalendarCache(repository: repository)
        let vm = CalendarListViewModel(mode: .active, cache: cache)

        await vm.fetch()

        await waitUntil { vm.calendars.count == 2 }
        #expect(vm.isLoading == false)
        #expect(vm.calendars.count == 2)
        #expect(vm.calendars[0].name == "Calendar 1")
        #expect(vm.calendars[1].name == "Calendar 2")
    }

    @Test("addCalendar creates new calendar")
    func addCalendar() async {
        let repository = InMemoryCalendarRepository()
        let cache = CalendarCache(repository: repository)
        let vm = CalendarListViewModel(mode: .active, cache: cache)

        vm.addCalendar(with: "New Test Calendar")

        await waitUntil { vm.calendars.count == 1 }
        #expect(vm.calendars[0].name == "New Test Calendar")

        let persisted = try? await repository.getActiveCalendars()
        #expect(persisted?.count == 1)
        #expect(persisted?.first?.name == "New Test Calendar")
    }

    @Test("archiveCalendarInList archives calendar")
    func archiveCalendarInList() async throws {
        let calendar = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let repository = InMemoryCalendarRepository(seed: [calendar])
        let cache = CalendarCache(repository: repository)
        let vm = CalendarListViewModel(mode: .active, cache: cache)

        await vm.fetch()
        await waitUntil { vm.calendars.count == 1 }

        vm.archiveCalendarInList(calendar)

        await waitUntil { vm.calendars.isEmpty }
        #expect(try await repository.getCalendar(id: 1)?.isArchived == true)
        let active = try await repository.getActiveCalendars()
        #expect(active.isEmpty)
    }

    @Test("restoreCalendarInList restores calendar")
    func restoreCalendarInList() async throws {
        let calendar = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3, isArchived: true)
        let repository = InMemoryCalendarRepository(seed: [calendar])
        let cache = CalendarCache(repository: repository)
        let vm = CalendarListViewModel(mode: .archived, cache: cache)

        await vm.fetch()
        await waitUntil { vm.calendars.count == 1 }

        vm.restoreCalendarInList(calendar)

        await waitUntil { vm.calendars.isEmpty }
        #expect(try await repository.getCalendar(id: 1)?.isArchived == false)
    }

    @Test("permanentlyDeleteCalendar removes calendar")
    func permanentlyDeleteCalendar() async throws {
        let calendar = CalendarDataSource(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let repository = InMemoryCalendarRepository(seed: [calendar])
        let cache = CalendarCache(repository: repository)
        let vm = CalendarListViewModel(mode: .active, cache: cache)

        await vm.fetch()
        await waitUntil { vm.calendars.count == 1 }

        vm.permanentlyDeleteCalendar(calendar)

        await waitUntil { vm.calendars.isEmpty }
        #expect(try await repository.getCalendar(id: 1) == nil)
    }
}