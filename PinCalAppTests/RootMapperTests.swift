//
//  RootMapperTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import Testing
import CoreDomain
// `@testable` for the internal `PP*` entities, which this suite asserts are untouched.
@testable import CorePersistence
@testable import PinCalApp

@MainActor
struct RootMapperTests {
    private let day = Date(timeIntervalSince1970: 1_780_000_000)
    private let mapper = RootMapper()

    // MARK: - DTO -> domain

    @Test("A DTO id of zero becomes a nil persisted id, not a zero")
    func zeroIdBecomesNil() {
        let staged = EventDataSource(id: 0, name: "New", date: day, color: "eventColorOption1")

        let event = mapper.event(from: staged)

        #expect(event.persistedID == nil, "id 0 is the 'not saved yet' sentinel and must not survive")
        #expect(!event.isPersisted)
    }

    @Test("A real DTO id becomes a persisted id")
    func realIdSurvives() {
        let saved = EventDataSource(id: 42, name: "Saved", date: day, color: "eventColorOption1")

        #expect(mapper.event(from: saved).persistedID == 42)
    }

    @Test("The DTO timestamp is dropped, because it was never persisted")
    func timestampIsDropped() {
        let dto = EventDataSource(
            id: 7, name: "X", date: day, color: "eventColorOption1", timestamp: UUID()
        )

        // `EventDataSource.init(_ dto: PPEvent?)` hard-sets timestamp to nil, so a
        // row read back from the store never has one. Mapping must not invent it.
        let event = mapper.event(from: dto)
        #expect(event.pendingID != dto.timestamp)
        #expect(event.persistedID == 7)
    }

    @Test("Mapping a batch preserves its content and sorts its events by date")
    func batchMapping() {
        let earlier = EventDataSource(id: 1, name: "Earlier", date: day, color: "eventColorOption1")
        let later = EventDataSource(id: 2, name: "Later", date: day.addingTimeInterval(3600), color: "eventColorOption1")
        let dto = EventBatchDataSource(
            id: 5,
            name: "Morning",
            colorName: "eventColorOption2",
            events: [later, earlier]
        )

        let batch = mapper.eventBatch(from: dto)

        #expect(batch.persistedID == 5)
        #expect(batch.name == "Morning")
        #expect(batch.colorName == "eventColorOption2")
        #expect(batch.events.map(\.name) == ["Earlier", "Later"], "the batch must arrive date-sorted")
        #expect(batch.date == day, "date is derived from the first event")
    }

    @Test("Each mapped row gets its own pending id, so staged rows stay distinguishable")
    func pendingIDsAreDistinct() {
        let dto = EventBatchDataSource(
            id: 0,
            name: "Staged",
            events: [
                EventDataSource(id: 0, name: "A", date: day, color: "eventColorOption1"),
                EventDataSource(id: 0, name: "B", date: day.addingTimeInterval(3600), color: "eventColorOption1"),
            ]
        )

        let batch = mapper.eventBatch(from: dto)

        #expect(batch.events[0].pendingID != batch.events[1].pendingID)
        #expect(batch.events[0].pendingID != batch.pendingID)
    }

    // MARK: - domain -> DTO

    @Test("A nil persisted id is written as id zero, so the store assigns one")
    func nilPersistedIDWritesZero() {
        let staged = CalendarEvent(name: "New", date: day, colorName: "eventColorOption1")

        let dto = mapper.eventDataSource(from: staged)

        #expect(dto.id == 0, "ObjectBox treats 0 as 'new' and assigns the id")
        #expect(dto.name == "New")
        #expect(dto.date == day)
        #expect(dto.color == "eventColorOption1")
    }

    @Test("A persisted id round-trips through the DTO unchanged")
    func persistedIDRoundTrips() {
        let saved = CalendarEvent(persistedID: 99, name: "Saved", date: day, colorName: "eventColorOption3")

        #expect(mapper.eventDataSource(from: saved).id == 99)
    }

    @Test("An empty batch writes id zero and a nil date")
    func emptyBatch() {
        let empty = CalendarEventBatch(name: "Empty")

        let dto = mapper.eventBatchDataSource(from: empty)

        #expect(dto.id == 0)
        #expect(dto.date == nil)
        #expect(dto.events.isEmpty)
    }

    @Test("A domain batch round-trips through the DTO and back")
    func roundTrip() {
        let original = CalendarEventBatch(
            persistedID: 12,
            name: "Round",
            colorName: "eventColorOption1",
            events: [
                CalendarEvent(persistedID: 1, name: "A", date: day, colorName: "eventColorOption1"),
                CalendarEvent(persistedID: 2, name: "B", date: day.addingTimeInterval(3600), colorName: "eventColorOption1"),
            ]
        )

        let restored = mapper.eventBatch(from: mapper.eventBatchDataSource(from: original))

        #expect(restored.persistedID == 12)
        #expect(restored.name == original.name)
        #expect(restored.colorName == original.colorName)
        #expect(restored.events.map(\.name) == ["A", "B"])
        #expect(restored.events.map(\.persistedID) == [1, 2])
        #expect(restored.hasSameContent(as: original, using: PCCalendarDataProvider()))
    }

    @Test("A staged batch round-trips as staged, never gaining an id")
    func stagedRoundTrip() {
        let staged = CalendarEventBatch(
            name: "Staged",
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "A", date: day, colorName: "eventColorOption1")]
        )

        let restored = mapper.eventBatch(from: mapper.eventBatchDataSource(from: staged))

        #expect(restored.persistedID == nil)
        #expect(restored.events[0].persistedID == nil)
    }

    @Test("Only the management fields are carried onto a PinCalendar")
    func calendarMapping() {
        let dto = CalendarDataSource(
            id: 3,
            name: "Work",
            year: 2026,
            numberOfColumns: 6,
            isArchived: true,
            eventBatches: [EventBatchDataSource(name: "B", events: [EventDataSource(name: "A", date: day, color: "eventColorOption1")])]
        )

        let calendar = mapper.calendar(from: dto)

        #expect(calendar.id == 3)
        #expect(calendar.name == "Work")
        #expect(calendar.year == 2026)
        #expect(calendar.numberOfColumns == 6)
        #expect(calendar.isArchived)
    }
}
