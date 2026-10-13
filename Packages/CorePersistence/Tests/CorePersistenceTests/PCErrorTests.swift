//
//  PCErrorTests.swift
//  CorePersistenceTests
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import Testing
@testable import CorePersistence

@Suite("PCError recording")
struct PCErrorTests {
    // MARK: - StorageError

    @Test("A missing batch records the batch it named")
    func batchMissingRecordsItsId() {
        let record = StorageError.batchMissing(id: 42).pcRecord()

        #expect(record.subject == .batch(id: 42))
        #expect(record.operation == "storage.saveCalendar")
    }

    @Test("A missing calendar records the calendar it named")
    func calendarMissingRecordsItsId() {
        let record = StorageError.calendarMissing(id: 7).pcRecord()

        #expect(record.subject == .calendar(id: 7))
    }

    /// A row in the table with no message is a row that cannot be acted on, and the failure mode
    /// is silent: `String(describing:)` on a type with a custom description could return empty.
    @Test("Every StorageError case produces a non-empty message", arguments: [
        StorageError.batchMissing(id: 1),
        StorageError.calendarMissing(id: 1)
    ])
    func storageErrorsProduceMessages(error: StorageError) {
        #expect(!error.pcRecord().message.isEmpty)
    }

    @Test("The fallback prefers a LocalizedError description over the type name")
    func fallbackPrefersLocalizedDescription() {
        struct Described: LocalizedError {
            var errorDescription: String? {
                "something readable"
            }
        }

        #expect(Described().pcFallbackMessage == "something readable")
        #expect(StorageError.batchMissing(id: 1).pcFallbackMessage == "StorageError")
    }

    // MARK: - Record

    /// The record owns its timestamp rather than having one stamped on it by whoever records it,
    /// so this pins that a caller can supply the moment the failure happened.
    @Test("A record keeps the timestamp it was given")
    func recordKeepsGivenTimestamp() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let record = PCErrorRecord(subject: .storage, operation: "op", message: "m", timestamp: when)

        #expect(record.timestamp == when)
    }
}
