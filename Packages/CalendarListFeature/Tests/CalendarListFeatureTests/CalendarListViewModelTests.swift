
import Foundation
import Testing
import CoreDomain
@testable import CalendarListFeature

// MARK: - In-memory CalendarManaging for Testing

/// In-memory `CalendarManaging` so the view model's own tests exercise its logic rather
/// than a store.
///
/// Before Stage 4b these tests stood up a real `CalendarCache` over an in-memory
/// repository. That is no longer reachable: the view model now takes the domain port, and
/// the only thing implementing it over a cache is `CalendarStore` in the app target.
/// Coverage of the layers underneath did not go away with the fake — it moved to where
/// those types live, in `CorePersistenceTests/CalendarCacheIntegrationTests` and
/// `PinCalAppTests/CalendarStoreTests`.
///
/// The fan-out shape is kept on purpose, which brings one trap with it: **a subscriber
/// that has not started iterating yet misses everything yielded to it.** Yielding to an
/// `AsyncStream` with no registered consumer is silently dropped, there is no replay to
/// The only failure these tests can produce.
///
/// A named case rather than `NSError(domain:code:)` so `#expect(throws:)` matches on
/// identity — `Equatable`, not stringly-compared, which is what makes the assertion below fail
/// if the wrong error is ever thrown.
enum TestError: Error, Equatable {
    case readFailed
    case writeFailed
}

/// catch up on. `CalendarStore` escapes this by registering with the cache before
/// `changes()` returns, and by the time anything writes in the real app the subscription
/// is long since live. A test, though, can write in the same instant it constructs the
/// view model — and then it is testing task-scheduling luck, not logic. Hence
/// `waitForSubscribers()`, which every fixture awaits.
actor InMemoryCalendarManaging: CalendarManaging {
    /// When set, the two loads throw this instead of answering.
    ///
    /// This exists because `loadActive`/`loadArchived` used to be non-throwing, which forced the
    /// implementation to swallow a failed read and return `[]` — and every test in this suite
    /// ran against a fake that could not fail, so nothing could tell the difference between "no
    /// calendars" and "the read broke". With the protocol now throwing, a fake that never throws
    /// leaves the new behaviour untested: a regression back to the empty-list path would pass
    /// silently. Tests that care set this; the rest never touch it.
    var loadError: Error?

    /// Arms or disarms the load failure. `nil` restores normal behaviour.
    func setLoadFailure(_ error: Error?) {
        loadError = error
    }

    private var calendars: [Int64: PinCalendar] = [:]
    private var nextID: Int64 = 1
    private var continuations: [UUID: AsyncStream<PinCalendarChange>.Continuation] = [:]
    private var subscriberWaiters: [CheckedContinuation<Void, Never>] = []

    init(seed: [PinCalendar] = []) {
        for calendar in seed {
            calendars[calendar.id] = calendar
            if calendar.id >= nextID {
                nextID = calendar.id + 1
            }
        }
    }

    // MARK: Subscribers

    nonisolated func changes() async -> AsyncStream<PinCalendarChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PinCalendarChange>.makeStream()
        // Registered before returning, not from inside the builder closure.
        await subscribe(id: id, continuation: continuation)
        continuation.onTermination = { _ in
            Task { await self.unsubscribe(id: id) }
        }
        return stream
    }

    private func subscribe(
        id: UUID,
        continuation: AsyncStream<PinCalendarChange>.Continuation
    ) {
        continuations[id] = continuation
        guard !subscriberWaiters.isEmpty else { return }
        let waiters = subscriberWaiters
        subscriberWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func unsubscribe(id: UUID) {
        continuations[id] = nil
    }

    /// Suspends until at least `count` subscribers are registered.
    ///
    /// Use this to place a barrier between "construct the view model" and "write", so a
    /// test asserts on behaviour rather than on which task the scheduler ran first.
    func waitForSubscribers(_ count: Int = 1) async {
        guard continuations.count < count else { return }
        await withCheckedContinuation { subscriberWaiters.append($0) }
    }

    private func broadcast(_ change: PinCalendarChange) {
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }

    // MARK: Reads

    /// `throws` and non-throwing, matching `CalendarManaging`.
    ///
    /// The protocol's loads throw, so a fake that does not forces every call site to carry a
    /// `try` that the compiler then reports as unnecessary — a warning in the very tests meant to
    /// pin the behaviour.
    ///
    /// Throws `loadError` when a test sets it, and nothing otherwise. The failure mode is the
    /// reason this fake exists in its present shape: before the protocol threw, a failed read
    /// and an empty list were the same value, so no test could tell them apart.
    func loadActive() throws -> [PinCalendar] {
        if let loadError {
            throw loadError
        }
        return sorted { !$0.isArchived }
    }

    func loadArchived() throws -> [PinCalendar] {
        if let loadError {
            throw loadError
        }
        return sorted(\.isArchived)
    }

    private func sorted(_ predicate: (PinCalendar) -> Bool) -> [PinCalendar] {
        calendars.values.filter(predicate).sorted { $0.id < $1.id }
    }

    /// Direct reads for assertions. The port deliberately offers no way to read a single
    /// calendar, so tests reach in here to check what actually landed in storage.
    func calendar(id: Int64) -> PinCalendar? {
        calendars[id]
    }

    func allCalendars() -> [PinCalendar] {
        sorted { _ in true }
    }

    // MARK: Writes

    /// When set, every write throws this and touches nothing.
    ///
    /// The mirror of `loadError`, and for the same reason. Before the writes reported failure,
    /// each one was a `try?` inside a `Task`, so nothing in this suite could observe one — and
    /// the most damaging case, an archive whose toast claimed success before the write was even
    /// attempted, was untestable rather than merely unhandled.
    var writeError: Error?

    /// Arms or disarms the write failure. `nil` restores normal behaviour.
    func setWriteFailure(_ error: Error?) {
        writeError = error
    }

    func createCalendar(name: String, year: Int, numberOfColumns: Int) throws {
        if let writeError {
            throw writeError
        }
        let id = nextID
        nextID += 1
        let calendar = PinCalendar(id: id, name: name, year: year, numberOfColumns: numberOfColumns)
        calendars[id] = calendar
        broadcast(.added(calendar))
    }

    func updateCalendar(_ calendar: PinCalendar) throws {
        if let writeError {
            throw writeError
        }
        guard calendars[calendar.id] != nil else { return }
        calendars[calendar.id] = calendar
        broadcast(.changed(calendar))
    }

    func archiveCalendar(id: Int64) throws {
        if let writeError {
            throw writeError
        }
        guard var calendar = calendars[id] else { return }
        calendar.isArchived = true
        calendars[id] = calendar
        broadcast(.removed(calendar))
    }

    func restoreCalendar(id: Int64) throws {
        if let writeError {
            throw writeError
        }
        guard var calendar = calendars[id] else { return }
        calendar.isArchived = false
        calendars[id] = calendar
        broadcast(.added(calendar))
    }

    func permanentlyDeleteCalendar(id: Int64) throws {
        if let writeError {
            throw writeError
        }
        guard let calendar = calendars.removeValue(forKey: id) else { return }
        broadcast(.removed(calendar))
    }
}

// MARK: - Helpers

/// Builds a view model over a seeded port, and returns only once the change feed is
/// live. See `InMemoryCalendarManaging` for why that barrier matters.
@MainActor
private func makeFixture(
    seed: [PinCalendar] = [],
    mode: CalendarListMode = .active
) async -> (managing: InMemoryCalendarManaging, viewModel: CalendarListViewModel) {
    let managing = InMemoryCalendarManaging(seed: seed)
    let viewModel = CalendarListViewModel(mode: mode, managing: managing)
    await managing.waitForSubscribers()
    return (managing, viewModel)
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
    func initialState() async {
        let (_, vm) = await makeFixture()

        #expect(vm.calendars.isEmpty)
        #expect(vm.isLoading == true)
        #expect(vm.displayMode == .list)
        #expect(vm.mode == .active)
    }

    @Test("Archived mode initializes with archived mode")
    func archivedMode() async {
        let (_, vm) = await makeFixture(mode: .archived)

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
    func addItem() async {
        let (_, vm) = await makeFixture()
        vm.addEditCalendarViewModel.id = 42
        vm.addEditCalendarViewModel.label = "Test"
        vm.addEditCalendarViewModel.calendar = PinCalendar(id: 7, name: "Existing", year: 2026, numberOfColumns: 3)

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
        vm.calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)

        vm.reset()

        #expect(vm.id == 0)
        #expect(vm.label == "")
        #expect(vm.calendar == nil)
    }
}

// MARK: - PinCalendar Tests

@Suite("PinCalendar Tests")
struct PinCalendarTests {
    @Test("PinCalendar is identifiable and hashable")
    func pinCalendarHashable() {
        let cal1 = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let cal2 = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let cal3 = PinCalendar(id: 2, name: "Other", year: 2026, numberOfColumns: 2)

        #expect(cal1 == cal2)
        #expect(cal1 != cal3)
        #expect(cal1.hashValue == cal2.hashValue)
    }

    @Test("PinCalendar isArchived defaults to false")
    func pinCalendarDefaultArchived() {
        let cal = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)

        #expect(cal.isArchived == false)
    }

    @Test("PinCalendar can be created with isArchived")
    func pinCalendarWithArchived() {
        let cal = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3, isArchived: true)

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

// MARK: - Integration Tests against the in-memory port

@MainActor
@Suite("CalendarListViewModel Integration Tests")
struct CalendarListViewModelIntegrationTests {
    @Test("fetch loads active calendars")
    func fetchActiveCalendars() async throws {
        let (_, vm) = await makeFixture(seed: [
            PinCalendar(id: 1, name: "Calendar 1", year: 2026, numberOfColumns: 3),
            PinCalendar(id: 2, name: "Calendar 2", year: 2026, numberOfColumns: 2),
        ])

        try await vm.fetch()

        #expect(vm.isLoading == false)
        #expect(vm.calendars.count == 2)
        #expect(vm.calendars[0].name == "Calendar 1")
        #expect(vm.calendars[1].name == "Calendar 2")
        #expect(vm.loadFailure == false)
    }

    /// The regression this whole change exists to prevent.
    ///
    /// A failed read used to return `[]`, which made a database error indistinguishable from an
    /// account with no calendars — the user was shown their data had vanished. The two
    /// requirements are separate and both are asserted: the failure is *reported*, and the
    /// already-loaded list is *not* replaced by an empty one.
    @Test("a failed load is recorded and does not empty the list")
    func failedLoadKeepsTheLastKnownList() async throws {
        let (managing, vm) = await makeFixture(seed: [
            PinCalendar(id: 1, name: "Calendar 1", year: 2026, numberOfColumns: 3),
        ])
        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        await managing.setLoadFailure(TestError.readFailed)
        await #expect(throws: TestError.readFailed) { try await vm.fetch() }

        #expect(vm.calendars.count == 1)
        #expect(vm.calendars[0].name == "Calendar 1")
        #expect(vm.isLoading == false)
        #expect(vm.loadFailure)
    }

    /// A later good read must clear the failure, or the error sticks after it stops being true.
    @Test("a successful load clears a previous failure")
    func successfulLoadClearsFailure() async throws {
        let (managing, vm) = await makeFixture(seed: [
            PinCalendar(id: 1, name: "Calendar 1", year: 2026, numberOfColumns: 3),
        ])

        await managing.setLoadFailure(TestError.readFailed)
        await #expect(throws: TestError.readFailed) { try await vm.fetch() }

        await managing.setLoadFailure(nil)
        try await vm.fetch()

        #expect(vm.loadFailure == false)
        #expect(vm.calendars.count == 1)
    }

    @Test("fetch in archived mode excludes active calendars")
    func fetchArchivedExcludesActive() async throws {
        let (_, vm) = await makeFixture(
            seed: [
                PinCalendar(id: 1, name: "Active", year: 2026, numberOfColumns: 3),
                PinCalendar(id: 2, name: "Archived", year: 2026, numberOfColumns: 3, isArchived: true),
            ],
            mode: .archived
        )

        try await vm.fetch()

        #expect(vm.calendars.count == 1)
        #expect(vm.calendars.first?.name == "Archived")
    }

    @Test("addCalendar creates new calendar")
    func addCalendar() async {
        let (managing, vm) = await makeFixture()

        vm.addCalendar(with: "New Test Calendar")

        await waitUntil { vm.calendars.count == 1 }
        #expect(vm.calendars.first?.name == "New Test Calendar")
        #expect(await managing.allCalendars().count == 1)
        #expect(await managing.allCalendars().first?.name == "New Test Calendar")
    }

    @Test("archiveCalendarInList archives immediately and shows undo toast")
    func archiveCalendarInList() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])

        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        vm.archiveCalendarInList(calendar)

        // The toast waits for the write to land. It used to be presented *before* the write was
        // attempted, so on failure the calendar sat in the list under a banner claiming it had
        // been archived — and the five-second undo window counted down over nothing.
        await waitUntil { vm.isArchiveToastPresented }
        #expect(vm.pendingArchive?.id == 1)
        await waitUntil { vm.calendars.isEmpty }
        #expect(await managing.calendar(id: 1)?.isArchived == true)
        #expect(try await managing.loadActive().isEmpty)
    }

    /// The regression the archive rewrite exists to prevent.
    ///
    /// Every part is asserted, because any one of them alone would pass on the old code: no
    /// toast (the claim), the calendar still in the list (the row), and a recorded failure the
    /// user can retry (the remedy).
    @Test("a failed archive shows no toast and keeps the calendar in the list")
    func failedArchiveIsNotReportedAsSuccess() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()

        await managing.setWriteFailure(TestError.writeFailed)
        vm.archiveCalendarInList(calendar)

        await waitUntil { vm.writeFailure != nil }
        #expect(vm.isArchiveToastPresented == false)
        #expect(vm.pendingArchive == nil)
        #expect(vm.calendars.count == 1)
        #expect(vm.calendars[0].id == 1)
        #expect(vm.writeFailure?.operation == .archive(calendarID: 1))
    }

    /// Retry re-runs the operation that failed, not whatever the list looks like now.
    @Test("retry re-runs the failed archive")
    func retryReRunsFailedArchive() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()

        await managing.setWriteFailure(TestError.writeFailed)
        vm.archiveCalendarInList(calendar)
        await waitUntil { vm.writeFailure != nil }

        await managing.setWriteFailure(nil)
        vm.retryWriteFailure()

        await waitUntil { vm.calendars.isEmpty }
        #expect(vm.writeFailure == nil)
        #expect(await managing.calendar(id: 1)?.isArchived == true)
    }

    /// A failed permanent delete must not look like a successful one.
    ///
    /// Specifically: no removal is published. The removal change drives `onCalendarRemoved`,
    /// which closes the detail column and clears the selection — so a failure that still broadcast
    /// would tear down the screen over a row that never went anywhere.
    @Test("a failed permanent delete does not publish a removal")
    func failedPermanentDeleteDoesNotRemove() async throws {
        let calendar = PinCalendar(id: 1, name: "Doomed", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        await managing.setWriteFailure(TestError.writeFailed)
        vm.permanentlyDeleteCalendar(calendar)

        await waitUntil { vm.writeFailure != nil }
        #expect(vm.writeFailure?.operation == .permanentlyDelete(calendarID: 1))
        #expect(vm.calendars.count == 1)
        #expect(await managing.calendar(id: 1) != nil)
    }

    @Test("undoArchive restores the calendar")
    func undoArchive() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])

        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        vm.archiveCalendarInList(calendar)
        await waitUntil { vm.calendars.isEmpty }
        #expect(vm.isArchiveToastPresented)

        vm.undoArchive()

        #expect(!vm.isArchiveToastPresented)
        #expect(vm.pendingArchive == nil)
        await waitUntil { vm.calendars.count == 1 }
        #expect(await managing.calendar(id: 1)?.isArchived == false)
    }

    @Test("restoreCalendarInList restores calendar")
    func restoreCalendarInList() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3, isArchived: true)
        let (managing, vm) = await makeFixture(seed: [calendar], mode: .archived)

        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        vm.restoreCalendarInList(calendar)

        await waitUntil { vm.calendars.isEmpty }
        // The list assertion is the point of this test: the store is easy, the visible
        // Archived list is what the user sees, and it is where a naive change fold puts
        // a restored calendar back in.
        #expect(vm.calendars.isEmpty)
        #expect(await managing.calendar(id: 1)?.isArchived == false)
    }

    @Test("permanentlyDeleteCalendar removes calendar")
    func permanentlyDeleteCalendar() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])

        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        vm.permanentlyDeleteCalendar(calendar)

        await waitUntil { vm.calendars.isEmpty }
        #expect(await managing.calendar(id: 1) == nil)
    }

    /// The list is the only screen watching calendars come and go, so it is what reports that one
    /// has gone — and whoever put a calendar on screen needs to hear it.
    ///
    /// Off the change feed, not off the archive and delete methods, which is the whole point of
    /// the assertion being here: it fires for the *effect*, so it cannot miss a route to those
    /// operations, and a write that failed produces nothing to report.
    @Test("A calendar leaving the active set is reported")
    func removalIsReported() async throws {
        let archived = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (_, vm) = await makeFixture(seed: [archived])

        var removed: [Int64] = []
        vm.onCalendarRemoved = { removed.append($0) }

        try await vm.fetch()
        vm.archiveCalendarInList(archived)
        await waitUntil { vm.calendars.isEmpty }

        #expect(removed == [1])
    }

    /// Announced after the list has folded the removal in, so a handler that re-reads the
    /// list does not see a calendar it has already been told is gone.
    @Test("The removal is reported once the list has folded it in")
    func removalIsReportedAfterTheList() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (_, vm) = await makeFixture(seed: [calendar])

        var wasAlreadyGone: Bool?
        vm.onCalendarRemoved = { [weak vm] _ in wasAlreadyGone = vm?.calendars.isEmpty }

        try await vm.fetch()
        vm.permanentlyDeleteCalendar(calendar)
        await waitUntil { wasAlreadyGone != nil }

        #expect(wasAlreadyGone == true)
    }

    /// Undo is not a removal. The archive toast offers to put the calendar back, and a close
    /// driven by that would take the calendar off screen for an operation the user is being
    /// invited to reverse.
    @Test("Undoing an archive is not reported as a removal")
    func undoIsNotReportedAsRemoval() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])

        var removed: [Int64] = []
        vm.onCalendarRemoved = { removed.append($0) }

        try await vm.fetch()
        vm.archiveCalendarInList(calendar)
        await waitUntil { vm.calendars.isEmpty }
        #expect(removed == [1], "precondition: the archive reported")

        vm.undoArchive()
        await waitUntil { vm.calendars.count == 1 }
        await managing.waitForSubscribers()

        #expect(removed == [1], "and only that once: a restore is a change, not a removal")
    }

    /// Deleting for good is reachable only from the archived list, and it is the case where a
    /// stale on-screen calendar has the least to say — the row is out of storage, so the detail
    /// fetches, finds nothing, and renders nothing at all.
    @Test("A permanent delete is reported from the archived list too")
    func permanentDeleteIsReportedFromTheArchivedList() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3, isArchived: true)
        let (_, vm) = await makeFixture(seed: [calendar], mode: .archived)

        var removed: [Int64] = []
        vm.onCalendarRemoved = { removed.append($0) }

        try await vm.fetch()
        vm.permanentlyDeleteCalendar(calendar)
        await waitUntil { vm.calendars.isEmpty }

        #expect(removed == [1])
    }

    @Test("rename from a card reaches the store")
    func renameReachesStore() async throws {
        let calendar = PinCalendar(id: 1, name: "Old Name", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])

        try await vm.fetch()
        #expect(vm.calendars.count == 1)

        // Driven through the card's own edit cycle, the way the UI does it, so the test
        // covers the callback wiring and not just the store call behind it.
        let card = vm.cardViewModel(for: calendar)
        card.startEditing()
        card.editingName = "New Name"
        card.confirmEdit()

        await waitUntil { vm.calendars.first?.name == "New Name" }
        #expect(await managing.calendar(id: 1)?.name == "New Name")
    }
}
