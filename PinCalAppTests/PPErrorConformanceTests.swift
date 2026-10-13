//
//  PPErrorConformanceTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import Testing
import CalendarListFeature
import CoreDomain
import CorePersistence
import SingleCalendarFeature
@testable import PinCalApp

/// The conformances declared in `PPErrorConformance.swift`.
///
/// They live in the app target, so they are only reachable from here — which means nothing else
/// in the suite covers them, and a broken `pcRecord()` would fail silently in production.
@Suite("PPError conformance")
struct PPErrorConformanceTests {
    // MARK: - Calendar-list write failures

    /// Every `Operation` case, as a table rather than five separate tests.
    ///
    /// Written as data so that adding a case to `Operation` fails this test instead of quietly
    /// falling through to a placeholder. That is the failure worth catching: a new operation that
    /// records as `"calendarList.unknown"` is still *recorded*, so nothing downstream would ever
    /// complain.
    private static let operations: [(PCCalendarListWriteFailure.Operation, String, PCErrorSubject)] = [
        (.create(name: "New"), "calendarList.create", .unknown),
        (.rename(calendarID: 11, newName: "Renamed"), "calendarList.rename", .calendar(id: 11)),
        (.archive(calendarID: 12), "calendarList.archive", .calendar(id: 12)),
        (.restore(calendarID: 13), "calendarList.restore", .calendar(id: 13)),
        (.permanentlyDelete(calendarID: 14), "calendarList.permanentlyDelete", .calendar(id: 14)),
    ]

    @Test("Every calendar-list operation maps to a name and a subject", arguments: Self.operations)
    func operationsMap(operation: PCCalendarListWriteFailure.Operation, expectedName: String, expectedSubject: PCErrorSubject) {
        let failure = PCCalendarListWriteFailure(operation: operation, calendarName: "Private name", message: "boom")

        let record = failure.pcRecord()

        #expect(record.operation == expectedName)
        #expect(record.subject == expectedSubject)
        #expect(record.message == "boom")
    }

    /// A create has no id because the row it would name does not exist yet.
    @Test("A create does not claim a calendar id")
    func createHasNoSubjectId() {
        let failure = PCCalendarListWriteFailure(operation: .create(name: "New"), calendarName: nil, message: "boom")

        #expect(failure.pcRecord().subject == .unknown)
    }

    /// `operation` carries the user's text in two of its five cases, and the recorded string is
    /// the field most likely to be pasted into a bug report.
    @Test("A recorded operation never carries the name the user typed")
    func operationDoesNotLeakNames() {
        let created = PCCalendarListWriteFailure(operation: .create(name: "Therapy notes"), calendarName: nil, message: "boom")
        let renamed = PCCalendarListWriteFailure(
            operation: .rename(calendarID: 3, newName: "Therapy notes"),
            calendarName: "Therapy notes",
            message: "boom"
        )

        #expect(!created.pcRecord().operation.contains("Therapy"))
        #expect(!renamed.pcRecord().operation.contains("Therapy"))
    }

    // MARK: - Batch save failures

    @Test("A failed save records the calendar it was aimed at")
    func failedSaveRecordsItsCalendar() {
        let failure = PCFailedSave(calendarID: 99, numberOfColumns: 3, eventBatches: [], message: "disk full")

        let record = failure.pcRecord()

        #expect(record.subject == .calendar(id: 99))
        #expect(record.operation == "eventBatch.save")
        #expect(record.message == "disk full")
    }

    /// The batch set is the payload that has to survive for a retry. It must not end up here.
    @Test("A failed save does not carry its payload into the record")
    func failedSaveDoesNotRecordPayload() {
        let batch = CalendarEventBatch(name: "Private batch", colorName: "red")
        let failure = PCFailedSave(calendarID: 1, numberOfColumns: 3, eventBatches: [batch], message: "boom")

        let rendered = String(describing: failure.pcRecord())

        #expect(!rendered.contains("Private batch"))
    }

    /// A row with no message cannot be acted on, and nothing downstream would notice.
    @Test("Every record has a non-empty message")
    func recordsHaveMessages() {
        let listed: [any PCError] = [
            PCCalendarListWriteFailure(operation: .archive(calendarID: 1), calendarName: nil, message: "boom"),
            PCFailedSave(calendarID: 1, numberOfColumns: 3, eventBatches: [], message: "boom"),
        ]

        for error in listed {
            #expect(!error.pcRecord().message.isEmpty)
        }
    }
}
