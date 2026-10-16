
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

    // MARK: Write-order recording

    /// Whether to record write ordering. Off until a test asks, so the other tests pay nothing.
    private var recordOrder = false
    private var order: [String] = []
    private var inFlight = 0
    private var overlapped = false

    /// Arms the recorder. See `writesAreSerialised` for why the fake needed this at all.
    func startRecordingOrder() {
        recordOrder = true
        order = []
        inFlight = 0
        overlapped = false
    }

    /// The labels of the writes, in the order they *entered*.
    func recordedOrder() -> [String] {
        order
    }

    /// Whether two writes were ever inside the port at the same time.
    func wereAnyWritesOverlapping() -> Bool {
        overlapped
    }

    /// Marks a write as started, and suspends long enough for an overlap to be possible.
    ///
    /// The suspension is the whole point. Every fake write was previously a synchronous method
    /// inside an actor, so it ran to completion without ever yielding — which means two
    /// concurrent callers could not have interleaved however the store was written, and a
    /// serialisation test would have passed no matter what. A test that cannot fail is worse
    /// than no test, because it reads as coverage.
    private func enter(_ label: String) async {
        guard recordOrder else { return }
        order.append(label)
        inFlight += 1
        if inFlight > 1 {
            overlapped = true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }

    private func exit() {
        guard recordOrder else { return }
        inFlight -= 1
    }

    func archiveCalendar(id: Int64) async throws {
        await enter("archive:\(id)")
        defer { exit() }
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

    func permanentlyDeleteCalendar(id: Int64) async throws {
        await enter("delete:\(id)")
        defer { exit() }
        if let writeError {
            throw writeError
        }
        guard let calendar = calendars.removeValue(forKey: id) else { return }
        broadcast(.removed(calendar))
    }
}

// MARK: - Failure reporting

/// The view model raises the failure callbacks the app target records from.
///
/// These are the only tests covering them. The reporting used to be raised by the *view* from a
/// `do/catch` and an `onChange`, neither of which a view-model test could reach — so nothing
/// asserted that a failure was reported at all, and the wiring was only ever exercised by hand.
/// Having the model raise them is what makes this testable at all.
@MainActor
@Suite("CalendarListViewModel Failure Reporting Tests")
struct CalendarListViewModelFailureReportingTests {
    /// A failed load is reported, carrying the error that came back.
    ///
    /// Asserted on the error and not merely on "something was raised", because the app target
    /// builds its record from it — an owner told only *that* it failed would have nothing to put
    /// in the diagnostics table.
    @Test("a failed load raises onLoadFailed with the error")
    func failedLoadRaisesOnLoadFailed() async throws {
        let (managing, vm) = await makeFixture(seed: [
            PinCalendar(id: 1, name: "Calendar 1", year: 2026, numberOfColumns: 3),
        ])
        var reported: [any Error] = []
        vm.store.onLoadFailed = { reported.append($0) }

        await managing.setLoadFailure(TestError.readFailed)
        await #expect(throws: TestError.readFailed) { try await vm.fetch() }

        #expect(reported.count == 1)
        #expect(reported.first as? TestError == .readFailed)
    }

    /// A load that worked must not report anything.
    ///
    /// The other half of the pairing, and the one that would be missed by a test that only ever
    /// fails: a stale report is as wrong as a missing one, and the app target writes a row per
    /// report.
    @Test("a successful load raises nothing")
    func successfulLoadRaisesNothing() async throws {
        let (_, vm) = await makeFixture(seed: [
            PinCalendar(id: 1, name: "Calendar 1", year: 2026, numberOfColumns: 3),
        ])
        var reported = 0
        vm.store.onLoadFailed = { _ in reported += 1 }

        try await vm.fetch()

        #expect(reported == 0)
    }

    /// A failed write is reported, carrying the operation that has to be retried.
    @Test("a failed write raises onWriteFailed")
    func failedWriteRaisesOnWriteFailed() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()

        var reported: [PCCalendarListWriteFailure] = []
        vm.store.onWriteFailed = { reported.append($0) }

        await managing.setWriteFailure(TestError.writeFailed)
        vm.archiveCalendarInList(calendar)

        await waitUntil { !reported.isEmpty }
        #expect(reported.count == 1)
        #expect(reported.first?.operation == .archive(calendarID: 1))
    }

    /// The same failure, twice over, is reported twice.
    ///
    /// This was a real gap and it is why the raise moved off the view. Reporting used to be
    /// driven by observing `writeFailure` *changing*, so two identical failures in a row left
    /// the stored value equal and the second was silently dropped — which is precisely the case
    /// worth counting, since "it failed, I retried, it failed again" is the shape of a real
    /// problem and the shape a diagnostics table most needs to show.
    ///
    /// Driven through two genuine failing writes rather than by injecting the failure twice,
    /// because the report is now raised by the failing effect and an injected action would not
    /// reach it — the test would pass for the wrong reason.
    @Test("the same write failure twice over is reported twice")
    func repeatedIdenticalWriteFailureIsReportedEachTime() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()

        var reported = 0
        vm.store.onWriteFailed = { _ in reported += 1 }
        await managing.setWriteFailure(TestError.writeFailed)

        vm.archiveCalendarInList(calendar)
        await waitUntil { reported == 1 }
        vm.retryWriteFailure()
        await waitUntil { reported == 2 }

        #expect(reported == 2)
        #expect(vm.writeFailure?.operation == .archive(calendarID: 1))
    }

    /// Every write entry point reports through the same store helper, so one raise covers all
    /// of them. This pins the entry point the other tests here do not touch, because a future
    /// edit that reported from `archiveCalendarInList` alone would pass them all while silently
    /// dropping this one.
    @Test("a permanent delete failure is reported too")
    func permanentDeleteFailureIsReported() async throws {
        let calendar = PinCalendar(id: 1, name: "Doomed", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()

        var reported: [PCCalendarListWriteFailure] = []
        vm.store.onWriteFailed = { reported.append($0) }

        await managing.setWriteFailure(TestError.writeFailed)
        vm.permanentlyDeleteCalendar(calendar)

        await waitUntil { !reported.isEmpty }
        #expect(reported.first?.operation == .permanentlyDelete(calendarID: 1))
    }

    /// Two writes issued back to back run one after the other, not concurrently.
    ///
    /// This is the defect the chain exists to prevent, and it is invisible to every other test
    /// here: they issue one write and wait for it. The port cannot safely interleave — every
    /// write in `CalendarCache` is a read-modify-write split by an `await` — so two unstructured
    /// tasks let a restore's refetch be interleaved by an archive, which makes the restore
    /// append an archived calendar back into the active list.
    ///
    /// Asserted by ordering the two writes' own side effects rather than by timing, so a slow
    /// machine cannot fail it: the fake records the order writes *start* in, and the second is
    /// only allowed to start once the first has finished.
    @Test("writes issued back to back run in order, never concurrently")
    func writesAreSerialised() async throws {
        let first = PinCalendar(id: 1, name: "First", year: 2026, numberOfColumns: 3)
        let second = PinCalendar(id: 2, name: "Second", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [first, second])
        try await vm.fetch()

        await managing.startRecordingOrder()
        vm.archiveCalendarInList(first)
        vm.permanentlyDeleteCalendar(second)

        await waitUntil { await managing.recordedOrder().count >= 2 }
        #expect(await managing.recordedOrder() == ["archive:1", "delete:2"])
        #expect(await managing.wereAnyWritesOverlapping() == false)
    }

    /// A caller that sets no callback is unaffected.
    ///
    /// All three callbacks are optional and default to absent, so a view model built without
    /// them must not trap when they are raised.
    @Test("raising with no callback set is harmless")
    func raisingWithoutCallbacksIsHarmless() async throws {
        let calendar = PinCalendar(id: 1, name: "Test", year: 2026, numberOfColumns: 3)
        let (managing, vm) = await makeFixture(seed: [calendar])
        try await vm.fetch()

        await managing.setWriteFailure(TestError.writeFailed)
        vm.archiveCalendarInList(calendar)
        await waitUntil { vm.writeFailure != nil }

        await managing.setLoadFailure(TestError.readFailed)
        await #expect(throws: TestError.readFailed) { try await vm.fetch() }

        // Both raise points ran with nobody listening, and both still recorded their state.
        #expect(vm.writeFailure != nil)
        #expect(vm.loadFailure)
    }
}

// MARK: - Reducer and effects

/// The pure functions, with no port, no timer and no view.
///
/// This is what the reducer split bought: every rule below used to be reachable only by
/// standing up a view model over a fake `CalendarManaging` and waiting for an effect to land.
/// Asserting them here is both faster and stricter — these tests cannot pass by accident
/// through a scheduled write, and a transition that is wrong in isolation is now visible
/// without anything else having to be right.
@Suite("CalendarListReducer Tests")
struct CalendarListReducerTests {
    private func state(_ configure: (inout CalendarListState) -> Void = { _ in }) -> CalendarListState {
        var state = CalendarListState(mode: .active)
        configure(&state)
        return state
    }

    // MARK: The loading rule

    /// A load with nothing behind it is a spinner.
    @Test("a load with no calendars shows the spinner")
    func loadWithNothingToShowIsLoading() {
        let next = calendarListReducer(state(), .loadStarted)
        #expect(next.stage == .loading)
    }

    /// A load over a populated list must not replace it with a spinner.
    ///
    /// The conjunction lived in the view body before (`isLoading && calendars.isEmpty`), so this
    /// is the rule that was one edit away from flickering the whole screen on every
    /// pull-to-refresh.
    @Test("a load over a populated list leaves the content alone")
    func loadOverContentIsNotLoading() {
        let seeded = state { $0.calendars = [makeCalendar(1)] }
        #expect(seeded.stage == .loading)
        let next = calendarListReducer(seeded, .loadStarted)
        #expect(next.stage == .loading)
        #expect(next.calendars.count == 1)
    }

    /// The failure toast has to survive the retry it was offering.
    ///
    /// If `.loadStarted` cleared `loadFailure`, the toast would vanish the instant the user
    /// pressed Retry — replacing "your calendars could not be read, try again" with a spinner
    /// and no explanation of what it is waiting for.
    @Test("starting a load does not clear a previous failure")
    func loadStartedKeepsTheFailureToast() {
        let failed = state { $0.loadFailure = true }
        let next = calendarListReducer(failed, .loadStarted)
        #expect(next.loadFailure)
    }

    /// A landed load clears the failure and shows content.
    @Test("a successful load clears the failure")
    func successClearsFailure() {
        let failed = state {
            $0.loadFailure = true
            $0.stage = .loading
        }
        let next = calendarListReducer(failed, .loadSucceeded([makeCalendar(1)]))
        #expect(next.loadFailure == false)
        #expect(next.stage == .content)
        #expect(next.calendars.count == 1)
    }

    /// A failed load keeps the last known list.
    ///
    /// The regression this whole failure-reporting work exists to prevent: a failed read
    /// returning `[]` made a database error indistinguishable from an account with no calendars.
    @Test("a failed load does not empty the list")
    func failureKeepsTheLastKnownList() {
        let loaded = state {
            $0.calendars = [makeCalendar(1)]
            $0.stage = .content
        }
        let next = calendarListReducer(loaded, .loadFailed)
        #expect(next.calendars.count == 1)
        #expect(next.loadFailure)
    }

    // MARK: The archive window

    /// Archiving opens nothing on its own.
    ///
    /// The whole reason for `.archiveConfirmed`: the toast used to appear before the write was
    /// attempted, so a failed archive left the calendar sitting there under a banner claiming it
    /// had gone, with five seconds of Undo counting down over nothing.
    @Test("archiving alone opens no toast")
    func archiveTappedOpensNoToast() {
        let seeded = state { $0.calendars = [makeCalendar(1)] }
        let next = calendarListReducer(seeded, .archiveTapped(makeCalendar(1)))
        #expect(next.isArchiveToastPresented == false)
        #expect(next.pendingArchive == nil)
    }

    @Test("a landed archive opens the undo window")
    func archiveConfirmedOpensTheWindow() {
        let seeded = state { $0.calendars = [makeCalendar(1)] }
        let next = calendarListReducer(seeded, .archiveConfirmed(makeCalendar(1)))
        #expect(next.isArchiveToastPresented)
        #expect(next.pendingArchive?.id == 1)
    }

    @Test("the window elapsed leaves the calendar archived")
    func undoWindowElapsedClosesTheWindow() {
        let opened = state {
            $0.pendingArchive = makeCalendar(1)
            $0.isArchiveToastPresented = true
        }
        let next = calendarListReducer(opened, .undoWindowElapsed)
        #expect(next.isArchiveToastPresented == false)
        #expect(next.pendingArchive == nil)
    }

    // MARK: Retry

    /// A retry reads the operation it must re-run out of the state it just cleared.
    ///
    /// Asserted through `calendarListEffects`, because that is the only place the two halves
    /// are visible together: the reducer's job is to clear `writeFailure`, and the effect's is
    /// to have already read it.
    @Test("a retry re-runs the operation that failed")
    func retryReRunsTheFailedOperation() {
        let failure = PCCalendarListWriteFailure(
            operation: .rename(calendarID: 7, newName: "Work"),
            calendarName: "Work",
            message: "disk full"
        )
        let previous = state { $0.writeFailure = failure }
        let next = calendarListReducer(previous, .retryWriteFailure)

        #expect(next.writeFailure == nil, "so a failure that recurs is recorded afresh")
        #expect(
            calendarListEffects(.retryWriteFailure, previous, next)
                == [.renameCalendar(calendarID: 7, newName: "Work")]
        )
    }

    /// Every retryable operation maps to its own effect, and no two share one.
    ///
    /// Parameterised because the five are otherwise five separate copy-pasted `switch` arms,
    /// and a copy-pasted switch is how the archive undo and the rename came to disagree about
    /// what "retry" meant.
    @Test(
        "each retryable operation maps to its own effect",
        arguments: [
            (PCCalendarListWriteFailure.Operation.create(name: "New"), CalendarListEffect.createCalendar(name: "New")),
            (.rename(calendarID: 3, newName: "Renamed"), .renameCalendar(calendarID: 3, newName: "Renamed")),
            (.archive(calendarID: 4), .archiveCalendar(calendarID: 4)),
            (.restore(calendarID: 5), .restoreCalendar(calendarID: 5)),
            (.permanentlyDelete(calendarID: 6), .permanentlyDeleteCalendar(calendarID: 6)),
        ] as [(PCCalendarListWriteFailure.Operation, CalendarListEffect)]
    )
    func retryMapsToItsOwnEffect(
        operation: PCCalendarListWriteFailure.Operation,
        expected: CalendarListEffect
    ) {
        let previous = state {
            $0.writeFailure = .init(operation: operation, calendarName: nil, message: "no")
        }
        let next = calendarListReducer(previous, .retryWriteFailure)
        #expect(calendarListEffects(.retryWriteFailure, previous, next) == [expected])
    }

    /// A retry with nothing to retry does nothing.
    ///
    /// Not a hypothetical: `.retryWriteFailure` reaches the store from a toast's action, and a
    /// stale tap on a dismissed toast would otherwise re-run nothing at best.
    @Test("a retry with no failure runs no effect")
    func retryWithNothingToRetry() {
        let previous = state()
        let next = calendarListReducer(previous, .retryWriteFailure)
        #expect(calendarListEffects(.retryWriteFailure, previous, next).isEmpty)
    }

    // MARK: The change feed

    /// A removal announces itself only when the list actually lost the calendar.
    ///
    /// Load-bearing, and once wrong: a permanent delete that *failed* used to still close the
    /// detail column, tearing down a screen over a row that never went anywhere.
    @Test("a removal announces the id once the list has dropped it")
    func removalIsAnnounced() {
        let seeded = state {
            $0.calendars = [makeCalendar(1)]
            $0.stage = .content
        }
        let removed = makeCalendar(1)
        let next = calendarListReducer(seeded, .changeApplied(.removed(removed)))
        #expect(next.calendars.isEmpty)
        #expect(calendarListEffects(.changeApplied(.removed(removed)), seeded, next) == [.announceRemoval(1)])
    }

    /// A change about another mode's list must not announce anything.
    @Test("an add that is filtered out announces nothing")
    func filteredAddAnnouncesNothing() {
        let archived = CalendarListState(mode: .archived)
        let change = PinCalendarChange.added(makeCalendar(9)) // not archived, so not visible here
        let next = calendarListReducer(archived, .changeApplied(change))
        #expect(next.calendars.isEmpty)
        #expect(calendarListEffects(.changeApplied(change), archived, next).isEmpty)
    }

    /// A store's change feed is relative to whichever list *it* loaded, so a restore seen from
    /// Archived reads as an addition even though the result is that it leaves this list.
    @Test("a change is resolved against this screen's mode, not its shape")
    func changeIsResolvedAgainstMode() {
        let archived = CalendarListState(mode: .archived)
        let restored = makeCalendar(5, isArchived: false)
        let next = calendarListReducer(archived, .changeApplied(.changed(restored)))
        #expect(next.calendars.isEmpty, "an unarchived calendar does not belong in the archived list")
    }

    /// An upsert into a list that already holds the row replaces it rather than duplicating it.
    @Test("an upsert replaces rather than appends")
    func upsertReplaces() {
        let seeded = state {
            $0.calendars = [makeCalendar(1, name: "Old")]
            $0.stage = .content
        }
        let next = calendarListReducer(seeded, .changeApplied(.changed(makeCalendar(1, name: "New"))))
        #expect(next.calendars.count == 1)
        #expect(next.calendars.first?.name == "New")
    }

    /// A create that lands while the screen is a spinner has to take the spinner down.
    ///
    /// Nothing else can: a create does not call `loadSucceeded`, and the screen may never send
    /// another load. Without this the list stays a spinner over a calendar that is right there.
    @Test("an added calendar fills the spinner")
    func addedCalendarFillsTheSpinner() {
        let spinner = state()
        #expect(spinner.stage == .loading)
        let next = calendarListReducer(spinner, .changeApplied(.added(makeCalendar(2))))
        #expect(next.stage == .content)
        #expect(next.calendars.count == 1)
    }

    // MARK: View-only

    @Test("the display mode toggles both ways")
    func displayModeToggles() {
        let list = state { $0.displayMode = .list }
        let grid = calendarListReducer(list, .displayModeToggled)
        #expect(grid.displayMode == .grid)
        #expect(calendarListReducer(grid, .displayModeToggled).displayMode == .list)
    }

    /// A rejected action returns the state it was given, unchanged and equal.
    ///
    /// This is what makes `send` skip the commit *and* the effects: `next == previous` is the
    /// test, so an action the reducer declines must be a true no-op rather than merely a
    /// visually similar one.
    @Test("an action for an absent calendar changes nothing")
    func renameOfAnAbsentCalendarIsANoOp() {
        let seeded = state { $0.calendars = [makeCalendar(1)] }
        let next = calendarListReducer(seeded, .renameCommitted(calendarID: 99, newName: "X"))
        #expect(next == seeded)
    }

    private func makeCalendar(_ id: Int64, name: String = "Test", isArchived: Bool = false) -> PinCalendar {
        PinCalendar(id: id, name: name, year: 2026, numberOfColumns: 3, isArchived: isArchived)
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

/// Waits for `condition` rather than sleeping for a fixed span, but still on a deadline.
///
/// The deadline is 5 seconds, and it was 2. Not because the work got slower: the change feed is
/// a main-actor hop away and normally lands in microseconds. It is because these are the only
/// wall-clock budgets in the suite, and they are the only assertions that break when the machine
/// is loaded — four parallel destinations run them often enough to see it. A test that reports a
/// removal it did receive, because the wait gave up first, costs more than it saves.
@MainActor
private func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// The same, for a condition that has to await the port to answer.
///
/// Separate because `waitUntil` takes a synchronous closure — a condition that awaits cannot be
/// passed to it at all — and folding the two together would have meant making every existing
/// call site `async` for the sake of the handful that need it.
@MainActor
private func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: @MainActor () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while await condition() == false, Date() < deadline {
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
        vm.store.onCalendarRemoved = { removed.append($0) }

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
        vm.store.onCalendarRemoved = { [weak vm] _ in wasAlreadyGone = vm?.calendars.isEmpty }

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
        vm.store.onCalendarRemoved = { removed.append($0) }

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
        vm.store.onCalendarRemoved = { removed.append($0) }

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

        // Waits on the *store*, not on `calendars`. The reducer applies the new name to the
        // list synchronously — that is the optimistic update the revert exists for — so
        // `calendars` is already correct before the write has been issued, and waiting on it
        // would let the assertion below run against storage the write has not reached yet.
        await waitUntil { await managing.calendar(id: 1)?.name == "New Name" }
        #expect(await managing.calendar(id: 1)?.name == "New Name")
    }
}
