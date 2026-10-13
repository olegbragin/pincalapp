//
//  ObjectBoxPCErrorReporterTests.swift
//  CorePersistenceTests
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import Testing
@testable import CorePersistence

/// The reporter, against a real ObjectBox store.
///
/// An in-memory store rather than a fake, because what is being tested is the part a fake would
/// have to reimplement: the put, the eviction, and the round trip through the entity. The failure
/// this guards against — reading a cap that is enforced against the wrong count — only exists in
/// the box.
@Suite("ObjectBoxPCErrorReporter")
struct ObjectBoxPCErrorReporterTests {
    /// Returns only the reporter.
    ///
    /// There is deliberately no test that closes the store underneath it: doing so means handing
    /// the `Store` into the reporter's initializer and then using it again, which Swift 6 rejects
    /// as `sending`. The property being guarded is "recording never throws", and that is enforced
    /// by `record` having no `throws` in its signature — the compiler rejects any caller that
    /// could have to handle a failure, which is a stronger guarantee than a test could assert.
    private func makeReporter() throws -> ObjectBoxPCErrorReporter {
        let store = try ObjectBoxFactory.makeInMemoryStore(named: "error-reporter-\(UUID().uuidString)")
        return ObjectBoxPCErrorReporter(store: store)
    }

    private func record(
        _ subject: PCErrorSubject,
        operation: String,
        at timestamp: Date = Date()
    ) -> PCErrorRecord {
        PCErrorRecord(subject: subject, operation: operation, message: "boom", timestamp: timestamp)
    }

    // MARK: - Round trip

    @Test("A recorded failure comes back as it went in")
    func roundTrip() async throws {
        let reporter = try makeReporter()
        let when = Date(timeIntervalSince1970: 1_000_000)

        await reporter.record(record(.calendar(id: 7), operation: "archive", at: when))

        let stored = await reporter.records()
        #expect(stored.count == 1)
        #expect(stored.first?.subject == .calendar(id: 7))
        #expect(stored.first?.operation == "archive")
        #expect(stored.first?.timestamp == when)
    }

    /// The subject is flattened into a kind and an id for storage. Every case has to survive that
    /// round trip, including the one with no id at all — a subject that silently decodes as
    /// `.calendar(id: 0)` would put a real-looking id next to unrelated failures.
    @Test("Every subject kind survives the round trip", arguments: [
        PCErrorSubject.calendar(id: 5),
        .batch(id: 6),
        .storage,
        .unknown,
    ])
    func subjectsRoundTrip(subject: PCErrorSubject) async throws {
        let reporter = try makeReporter()

        await reporter.record(record(subject, operation: "op"))

        #expect(await reporter.records().first?.subject == subject)
    }

    @Test("An error can be recorded without being reduced first")
    func recordsFromPCError() async throws {
        let reporter = try makeReporter()

        await reporter.record(StorageError.batchMissing(id: 3))

        let stored = await reporter.records()
        #expect(stored.count == 1)
        #expect(stored.first?.subject == .batch(id: 3))
        #expect(stored.first?.operation == "storage.saveCalendar")
    }

    // MARK: - Ordering

    /// A table a person reads has to be in the order things happened, and that order comes from
    /// the timestamps rather than from insertion — a device coming back from offline with a
    /// corrected clock writes an older failure into a newer table.
    @Test("Records come back oldest first, whatever order they went in")
    func orderedByTimestamp() async throws {
        let reporter = try makeReporter()
        let base = Date(timeIntervalSince1970: 1_000_000)

        await reporter.record(record(.storage, operation: "third", at: base.addingTimeInterval(30)))
        await reporter.record(record(.storage, operation: "first", at: base))
        await reporter.record(record(.storage, operation: "second", at: base.addingTimeInterval(15)))

        #expect(await reporter.records().map(\.operation) == ["first", "second", "third"])
    }

    // MARK: - Capacity

    @Test("The table is capped, keeping the newest")
    func capsOldest() async throws {
        let reporter = try makeReporter()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let total = ObjectBoxPCErrorReporter.capacity + 10

        for index in 0..<total {
            await reporter.record(record(.storage, operation: "op-\(index)", at: base.addingTimeInterval(Double(index))))
        }

        let stored = await reporter.records()
        #expect(stored.count == ObjectBoxPCErrorReporter.capacity)
        // The ten that fell off are the oldest, so the newest survives.
        #expect(stored.first?.operation == "op-10")
        #expect(stored.last?.operation == "op-\(total - 1)")
    }

    @Test("Recording below the cap evicts nothing")
    func underCapKeepsEverything() async throws {
        let reporter = try makeReporter()

        for index in 0..<10 {
            await reporter.record(record(.storage, operation: "op-\(index)"))
        }

        #expect(await reporter.records().count == 10)
    }

    /// A crash loop is exactly when someone opens this screen, so the bound has to hold under
    /// repeated overflow rather than only on the first one.
    @Test("The cap still holds after further overflow")
    func capHoldsAcrossWaves() async throws {
        let reporter = try makeReporter()
        let base = Date(timeIntervalSince1970: 1_000_000)

        for index in 0..<(ObjectBoxPCErrorReporter.capacity * 2) {
            await reporter.record(record(.storage, operation: "op-\(index)", at: base.addingTimeInterval(Double(index))))
        }

        #expect(await reporter.records().count == ObjectBoxPCErrorReporter.capacity)
    }

    // MARK: - Clearing

    @Test("Clearing empties the table")
    func clearEmpties() async throws {
        let reporter = try makeReporter()
        await reporter.record(record(.storage, operation: "op"))

        await reporter.clear()

        #expect(await reporter.records().isEmpty)
    }
}
