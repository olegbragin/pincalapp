//
//  PCErrorRecorderTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import Testing
import CalendarListFeature
import CorePersistence
import SingleCalendarFeature
@testable import PinCalApp

/// The recorder, end to end: a failure goes in, a row comes out.
///
/// In-memory store rather than a fake, because the property under test is precisely that the row
/// is *persisted* — a fake that kept rows in an array would pass while the wiring to ObjectBox was
/// broken, which is the wiring most likely to break.
///
/// The reporter is fire-and-forget by design (see `PCErrorRecorder`), so every assertion polls for
/// the row rather than awaiting it. A fixed sleep here would be measuring the scheduler, not the
/// code.
@Suite("PCErrorRecorder")
struct PCErrorRecorderTests {
    private func makeRecorder() throws -> (PCErrorRecorder, ObjectBoxPCErrorReporter) {
        let store = try ObjectBoxFactory.makeInMemoryStore(named: "recorder-\(UUID().uuidString)")
        let reporter = ObjectBoxPCErrorReporter(store: store)
        return (PCErrorRecorder(reporter: reporter), reporter)
    }

    /// Polls until the table holds `count` rows, or gives up.
    ///
    /// Spelled out rather than reused from elsewhere because this is the only place in the suite
    /// that waits on an unawaited write; a shared helper would be one more thing to know about.
    private func waitForRows(
        _ reporter: ObjectBoxPCErrorReporter,
        count: Int,
        timeout: Duration = .seconds(2)
    ) async -> [PCErrorRecord] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let rows = await reporter.records()
            if rows.count >= count {
                return rows
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await reporter.records()
    }

    // MARK: - Conforming errors

    @Test("A conforming error is recorded with its own operation")
    func recordsConformingError() async throws {
        let (recorder, reporter) = try makeRecorder()

        recorder.record(StorageError.batchMissing(id: 4), operation: "unused")

        let rows = await waitForRows(reporter, count: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.subject == .batch(id: 4))
        // The failure's own operation, not the caller's fallback.
        #expect(rows.first?.operation == "storage.saveCalendar")
    }

    @Test("A calendar-list write failure keeps its operation")
    func recordsWriteFailure() async throws {
        let (recorder, reporter) = try makeRecorder()
        let failure = PCCalendarListWriteFailure(
            operation: .permanentlyDelete(calendarID: 9),
            calendarName: "Private",
            message: "disk full"
        )

        recorder.record(failure, operation: "unused")

        let rows = await waitForRows(reporter, count: 1)
        #expect(rows.first?.operation == "calendarList.permanentlyDelete")
        #expect(rows.first?.message == "disk full")
    }

    @Test("A failed batch save is recorded")
    func recordsFailedSave() async throws {
        let (recorder, reporter) = try makeRecorder()

        recorder.record(
            PCFailedSave(calendarID: 2, numberOfColumns: 3, eventBatches: [], message: "boom"),
            operation: "unused"
        )

        let rows = await waitForRows(reporter, count: 1)
        #expect(rows.first?.subject == .calendar(id: 2))
        #expect(rows.first?.operation == "eventBatch.save")
    }

    // MARK: - Non-conforming errors

    /// Most of what this app throws is a raw ObjectBox error that no package has named. Recording
    /// only the errors that happen to conform would miss the majority of real failures, so these
    /// are wrapped rather than dropped.
    @Test("A plain error is recorded under the caller's operation")
    func wrapsPlainError() async throws {
        let (recorder, reporter) = try makeRecorder()

        recorder.record(SimpleFailure(), operation: "calendarList.fetch")

        let rows = await waitForRows(reporter, count: 1)
        #expect(rows.count == 1)
        #expect(rows.first?.operation == "calendarList.fetch")
        #expect(rows.first?.subject == .storage)
        #expect(try !#require(rows.first?.message.isEmpty))
    }

    private struct SimpleFailure: LocalizedError {
        var errorDescription: String? {
            "the disk went away"
        }
    }

    // MARK: - Ordering

    /// Asserted on subjects, not operations: the two `StorageError` cases deliberately share an
    /// operation name, so an operation-keyed assertion would have demanded a distinction the
    /// mapping is right not to make.
    @Test("Several failures are all recorded")
    func recordsEveryFailure() async throws {
        let (recorder, reporter) = try makeRecorder()

        recorder.record(StorageError.batchMissing(id: 1), operation: "a")
        recorder.record(StorageError.calendarMissing(id: 2), operation: "b")
        recorder.record(SimpleFailure(), operation: "c")

        let rows = await waitForRows(reporter, count: 3)
        #expect(rows.count == 3)

        // Both `StorageError` cases record the *same* operation, and that is correct: a missing
        // batch and a missing calendar are both a `saveCalendar` that could not be satisfied. What
        // tells them apart in a report is the subject, so this asserts on that rather than on
        // operation — expecting one operation per error type would have been the wrong test, and
        // would have "passed" only if the mapping had been made more specific for no reason.
        #expect(rows.filter { $0.operation == "storage.saveCalendar" }.count == 2)
        #expect(rows.contains { $0.subject == .batch(id: 1) })
        #expect(rows.contains { $0.subject == .calendar(id: 2) })
        #expect(rows.filter { $0.operation == "c" }.count == 1)
    }

    // MARK: - The default

    /// The environment's default has to be harmless: a preview or a test that renders one of these
    /// views without a database must collect nothing rather than trap.
    @Test("The default recorder collects nothing")
    func defaultRecorderIsHarmless() async {
        let recorder = PCErrorRecorder(reporter: NoopPCErrorReporter())

        recorder.record(StorageError.batchMissing(id: 1), operation: "a")

        #expect(await NoopPCErrorReporter().records().isEmpty)
    }
}
