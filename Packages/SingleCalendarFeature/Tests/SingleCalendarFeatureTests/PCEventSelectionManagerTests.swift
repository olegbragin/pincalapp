//
//  PCEventSelectionManagerTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 29.09.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// Records every write, and how long it held the port for.
///
/// The delay is the point. Without it, writes that are *not* ordered can still appear to
/// arrive in order, so the ordering test would pass against a store that has none. Sleeping
/// in the middle of each write means any two writes that overlap will interleave in
/// `log`, which is exactly the bug `writeChain` exists to make unrepresentable.
actor RecordingCalendarPersisting: CalendarPersisting {

    enum Entry: Equatable {
        case begin(columns: Int, calendarID: Int64)
        case end(columns: Int, calendarID: Int64)
    }

    private(set) var log: [Entry] = []
    private let delay: Duration

    init(delay: Duration = .milliseconds(5)) {
        self.delay = delay
    }

    func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws {
        log.append(.begin(columns: numberOfColumns, calendarID: id))
        try? await Task.sleep(for: delay)
        log.append(.end(columns: numberOfColumns, calendarID: id))
    }

    func calendar(id: Int64) async throws -> PinCalendar? { nil }

    func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch] { [] }

    /// The deepest nesting ever reached, which is 1 exactly when no two writes overlapped.
    var maximumOverlap: Int {
        var depth = 0
        var peak = 0
        for entry in log {
            switch entry {
            case .begin: depth += 1
            case .end: depth -= 1
            }
            peak = max(peak, depth)
        }
        return peak
    }

    var writtenColumns: [Int] {
        log.compactMap { entry in
            if case .end(let columns, _) = entry { return columns }
            return nil
        }
    }
}

@MainActor
extension RecordingCalendarPersisting {

    /// Waits until `expected` writes have landed, or the deadline passes.
    ///
    /// A fixed sleep is the wrong tool here and was a real flake: the write chain is
    /// drained by the scheduler, so how long that takes depends on the machine, and a
    /// busy one can still be mid-chain when a 500 ms sleep expires — which reads as
    /// "writes were lost" rather than "the test gave up waiting". Polling for the
    /// condition distinguishes those two.
    func waitForWrites(_ expected: Int, timeout: Duration = .seconds(5)) async -> [Int] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let columns = await writtenColumns
            if columns.count >= expected { return columns }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await writtenColumns
    }
}

/// Fails every write once armed, and records the payloads it was asked to persist.
actor FailingCalendarPersisting: CalendarPersisting {
    private(set) var attempts: [(columns: Int, calendarID: Int64)] = []
    private var shouldFail = false

    func failFromNowOn() { shouldFail = true }
    func succeedFromNowOn() { shouldFail = false }

    func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws {
        attempts.append((numberOfColumns, id))
        if shouldFail {
            throw PersistenceStubError.diskFull
        }
    }

    func calendar(id: Int64) async throws -> PinCalendar? { nil }
    func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch] { [] }

    func attemptCount() -> Int { attempts.count }
}

enum PersistenceStubError: Error {
    case diskFull
}

@MainActor
extension FailingCalendarPersisting {
    /// Waits for at least `expected` attempts, so a test is not racing the chain.
    func waitForAttempts(_ expected: Int, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await attemptCount() >= expected { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
@Suite("PCEventSelectionManager")
struct PCEventSelectionManagerTests {

    private let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ dayOfMonth: Int, month: Int = 6, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        return gregorian.date(from: components)!
    }

    private func batch(
        _ name: String,
        on dayOfMonth: Int,
        id: Int64? = nil,
        color: String = "eventColorOption1"
    ) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: id,
            name: name,
            colorName: color,
            events: [CalendarEvent(name: "Event", date: day(dayOfMonth), colorName: color)]
        )
    }

    /// A store opened on `calendarID` with `batches` already synced, which is the shape
    /// every store test needs: `perform` refuses to write against calendar 0, so a store
    /// that has never synced has nothing to test.
    private func makeStore(
        calendarID: Int64 = 42,
        batches: [CalendarEventBatch] = [],
        persistence: any CalendarPersisting,
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

    // MARK: State is the reducer's, verbatim

    @Test("The store's state is exactly what the reducer returned")
    func stateIsTheReducers() {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(persistence: persistence)

        store.send(.startNewBatch(on: day(4)))

        #expect(store.state.stage == .batchEditor)
        #expect(store.state.assembly != nil)
        #expect(store.state.day == day(4))
    }

    @Test("A rejected action leaves the state untouched")
    func rejectedActionLeavesStateAlone() {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(persistence: persistence)

        let before = store.state
        // A batch with no name cannot be committed, so the reducer must decline. The name
        // is cleared explicitly: a new batch arrives named (§5.4), so "unnamed" is now a
        // state the user reaches rather than the one they start in. What is under test is
        // that a declined action is inert, and that has to be set up deliberately.
        store.send(.startNewBatch(on: day(4)))
        store.send(.setBatchName(""))
        let staged = store.state
        #expect(!staged.canSave, "precondition: the batch really is unsavable")
        store.send(.commitTapped)
        let afterCommit = store.state

        #expect(afterCommit.batches == before.batches, "an unsavable batch writes nothing")
        #expect(afterCommit.stage == .batchEditor, "and it does not close either")
    }

    // MARK: §12.3 — the reported duplicate-batch bug

    @Test("A staged batch that comes back under a real id is adopted, and the next commit updates that row")
    func syncAdoptsTheStagedBatch() async throws {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(persistence: persistence)

        store.send(.startNewBatch(on: day(2)))
        store.send(.setBatchName("morning"))
        let staged = try #require(store.state.assembly?.batch)
        let provider = store.state.dataProvider

        // A reloaded row: identical content, but the store assigned a persisted id, the day
        // is a different instant of the same day, and `pendingID` is fresh because a DTO
        // carries none. Only those three differ, so adoption has to be content-based.
        let reloaded = CalendarEventBatch(
            persistedID: 77,
            name: staged.name,
            colorName: staged.colorName,
            events: [
                CalendarEvent(
                    name: staged.events[0].name,
                    date: provider.startOfDay(for: day(2)),
                    colorName: staged.events[0].colorName
                )
            ]
        )
        store.send(.syncCalendar(calendarID: 42, batches: [reloaded]))

        #expect(store.state.assembly?.adoptedPersistedID == 77)

        store.send(.commitTapped)

        #expect(store.state.batches.count == 1, "one row, not a duplicate")
        #expect(store.state.batches.first?.persistedID == 77, "and it is the adopted row")
    }

    // MARK: §12.3 — write ordering

    @Test("Rapid column changes write sequentially and the last write is the final state")
    func writesAreSequentialAndTheLastIsTheFinalState() async throws {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(persistence: persistence)

        // 1...4 without awaiting between them: every write is queued before any of them has
        // had a chance to finish.
        for columns in 1...4 {
            store.send(.setNumberOfColumns(columns))
        }

        let columns = await persistence.waitForWrites(4)
        let recorded = await persistence.log
        let overlap = await persistence.maximumOverlap

        #expect(overlap == 1, "writes overlapped: \(recorded)")
        #expect(columns == [1, 2, 3, 4], "and they landed out of order")
        #expect(store.state.numberOfColumns == 4)
    }

    @Test("A write for calendar 0 never reaches the port")
    func writeIsSkippedWithoutACalendar() async {
        let persistence = RecordingCalendarPersisting()
        let store = PCEventSelectionManager(
            initialState: PCEventSelectionState(dataProvider: PCCalendarDataProvider()),
            persistence: persistence,
            daySelectionManager: PCCalendarDaySelectionManager()
        )

        // No `syncCalendar` first, so `calendarID` is still 0.
        store.send(.setNumberOfColumns(2))
        // Nothing should arrive; give the chain the same chance to be wrong as the
        // ordering test does before concluding it stayed quiet.
        _ = await persistence.waitForWrites(1, timeout: .milliseconds(300))
        let recorded = await persistence.log

        #expect(recorded.isEmpty, "there is no calendar 0 to write to")
        #expect(store.state.numberOfColumns == 2, "but the state still moved")
    }

    // MARK: Failed writes

    @Test("A failed save is recorded instead of swallowed, and blocks the calendar switch")
    func failedSaveIsRecordedAndBlocksSwitch() async {
        let persistence = FailingCalendarPersisting()
        let store = makeStore(calendarID: 42, persistence: persistence)

        await persistence.failFromNowOn()
        store.send(.setNumberOfColumns(6))
        await persistence.waitForAttempts(1)

        // Polled rather than slept: the chain runs on the scheduler, so a fixed wait would be
        // a flake that reads as "the failure was lost" instead of "the test gave up".
        var deadline = ContinuousClock.now + .seconds(5)
        while store.failedSave == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let failure = try! #require(store.failedSave)
        #expect(failure.calendarID == 42)
        #expect(failure.numberOfColumns == 6, "the payload that failed is what gets retried")
        #expect(!store.canSwitchCalendar, "an unsaved write must not be switchable-away-from")
    }

    @Test("Retrying replays the failed write and unblocks the switch once it lands")
    func retryReplaysTheFailedWrite() async {
        let persistence = FailingCalendarPersisting()
        let store = makeStore(calendarID: 42, persistence: persistence)

        await persistence.failFromNowOn()
        store.send(.setNumberOfColumns(6))
        await persistence.waitForAttempts(1)

        var deadline = ContinuousClock.now + .seconds(5)
        while store.failedSave == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.failedSave != nil)

        await persistence.succeedFromNowOn()
        store.retryFailedSave()
        await persistence.waitForAttempts(2)

        deadline = ContinuousClock.now + .seconds(5)
        while store.failedSave != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.failedSave == nil, "a landed retry clears the block")
        #expect(store.canSwitchCalendar)
    }

    @Test("In-flight writes do not block the calendar switch")
    func inFlightWritesDoNotBlockSwitch() async {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(calendarID: 42, persistence: persistence)

        store.send(.setNumberOfColumns(4))

        // Deliberately *not* awaited: the point is that a pending write is not a reason to
        // block. The switch flushes it; only a failure is a blocker.
        #expect(store.canSwitchCalendar, "blocking on every autosave would make the calendar sticky")
    }

    // MARK: Projection

    @Test("The projected year model carries the state's markers")
    func projectionCarriesMarkers() {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(
            batches: [batch("morning", on: 4, color: "eventColorOption3")],
            persistence: persistence
        )

        let marked = store.yearModel.months
            .flatMap(\.weeks)
            .flatMap(\.days)
            .filter { $0.events.isEmpty == false }
        #expect(marked.count == 1, "one day carries a marker")
        #expect(marked.first?.events == ["eventColorOption3"])
    }

    @Test("The year model keeps its day-model instances when only markers change")
    func projectionDoesNotRebuildUnnecessarily() {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(persistence: persistence)

        let before = store.yearModel.months.flatMap(\.weeks).flatMap(\.days)
        store.send(.setBatchColor(nil))
        let after = store.yearModel.months.flatMap(\.weeks).flatMap(\.days)

        #expect(before.count == after.count)
        #expect(zip(before, after).allSatisfy { $0 === $1 }, "the views bind to these instances")
    }

    @Test("A changed column count rebuilds the year model through the resolver")
    func columnCountRebuildsThroughTheResolver() {
        let persistence = RecordingCalendarPersisting()
        let store = makeStore(
            persistence: persistence,
            columnCountResolver: { _ in 1 } // the `-UITestColumns` override
        )

        #expect(store.yearModel.numberOfColumns == 1, "the resolver decides the real count")
        #expect(store.state.numberOfColumns == 3, "and the state keeps the requested one")
    }

    // MARK: §12.3 — the import list

    /// The store must not be able to name the storage layer.
    ///
    /// `CalendarPersisting` is the whole reason the port exists, and a store that can
    /// `import CorePersistence` can reach `CalendarDataSource`, `EventBatchDataSource` and
    /// `CalendarCache` without anyone noticing — there is no compiler error for it, and the
    /// DTO boundary the plan spends §3 on quietly stops holding. So it is asserted, not
    /// reviewed: the plan calls for exactly this ("a grep-based test or a lint rule in
    /// CI"), and this is the grep.
    @Test("The store's imports name the port, never the storage layer")
    func storeDoesNotImportCorePersistence() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SingleCalendarFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SingleCalendarFeature (the package root)
        let source = packageRoot
            .appendingPathComponent("Sources/SingleCalendarFeature/Model/Selection/PCEventSelectionManager.swift")

        let contents = try String(contentsOf: source, encoding: .utf8)
        let imports = contents
            .split(separator: "\n")
            .filter { $0.hasPrefix("import ") }

        #expect(!imports.isEmpty, "the file has no imports at all, so this test proves nothing")
        #expect(
            !imports.contains { $0 == "import CorePersistence" },
            "the store must depend on `CalendarPersisting`, not on CorePersistence"
        )
        #expect(
            imports.contains("import CoreDomain") && imports.contains("import DSKit"),
            "the port and the render target are both named: \(imports)"
        )
    }

    /// Stage 9's gate: the package must be off `CorePersistence` entirely.
    ///
    /// `SingleCalendarModel` held the last one, for the calendar's metadata change feed.
    /// That feed is not batch state, so it never belonged on `CalendarPersisting`, and it
    /// is not storage, so the feature should not name the storage vocabulary to get it —
    /// `CalendarManaging` carries it. The test is over *every* source file, not just the
    /// one that changed: an import that creeps back into any file in the package is the
    /// same regression, and a per-file check would only catch the one someone thought of.
    @Test("No file in the package imports CorePersistence")
    func packageDoesNotImportCorePersistence() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SingleCalendarFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SingleCalendarFeature (the package root)
        let sources = packageRoot.appendingPathComponent("Sources/SingleCalendarFeature")

        let offenders = try FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .compactMap { url -> String? in
                let contents = try String(contentsOf: url, encoding: .utf8)
                guard contents.split(separator: "\n").contains("import CorePersistence") else {
                    return nil
                }
                return url.lastPathComponent
            } ?? []

        #expect(
            offenders.isEmpty,
            "these files still name the storage layer: \(offenders.sorted())"
        )
    }
}
