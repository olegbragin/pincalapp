import Foundation
import Testing
import CoreDomain

@Suite("Batch Assembly Domain Models Tests")
struct BatchAssemblyDomainModelTests {

    /// Pinned to UTC so the day-boundary arithmetic below cannot shift under a
    /// simulator whose time zone is not the host's.
    private static func makeGregorian() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// The domain layer's only `Foundation.Calendar` owner. Every day comparison in
    /// these tests goes through it.
    ///
    /// Its time zone and locale are forced to the current ones by `init`, so a
    /// fixture calendar cannot pin them. Fixture dates are therefore built with a
    /// bare gregorian calendar and the assertions are written to hold in whatever
    /// time zone the tests run in.
    private let provider = PCCalendarDataProvider()
    /// A bare `Calendar` for building fixture dates.
    private let gregorian: Calendar = BatchAssemblyDomainModelTests.makeGregorian()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        return gregorian.date(from: components)!
    }

    private func event(
        _ name: String = "Event",
        on dayOfMonth: Int,
        month: Int = 6,
        color: String = "eventColorOption1"
    ) -> CalendarEvent {
        let date = day(2026, month, dayOfMonth)
        return CalendarEvent(name: name, date: date, colorName: color)
    }

    // MARK: - CalendarEvent

    @Test("Event identity is the pending id, not a zero sentinel")
    func eventIdentity() {
        let a = event("A", on: 1)
        let b = event("B", on: 1)

        #expect(a.id != b.id)
        #expect(a.id == a.pendingID)
        #expect(!a.isPersisted)
    }

    @Test("Event with(persistedID:) changes only the persisted id")
    func eventWithPersistedID() {
        let a = event("A", on: 1)
        let b = a.with(persistedID: 7)

        #expect(b.persistedID == 7)
        #expect(b.isPersisted)
        #expect(b.id == a.id, "A new persisted id must not change view identity")
        #expect(b.name == a.name && b.date == a.date && b.colorName == a.colorName)
    }

    @Test("Event with(pendingID:) replaces the pending id and keeps the persisted one")
    func eventWithPendingID() {
        let a = event("A", on: 1).with(persistedID: 7)
        let b = a.with(pendingID: UUID())

        #expect(b.id != a.id)
        #expect(b.persistedID == 7)
        #expect(b.name == a.name && b.date == a.date)
    }

    @Test("Event with(date:) keeps identity and moves the day")
    func eventWithDate() {
        let a = event("A", on: 1)
        let b = a.with(date: day(2026, 6, 9))

        #expect(b.date == day(2026, 6, 9))
        #expect(b.id == a.id, "moving an event must not change its identity")
    }

    // MARK: - CalendarEventBatch

    @Test("Batch sorts events by date on construction")
    func batchSortsOnInit() {
        let batch = CalendarEventBatch(
            name: "B",
            colorName: "eventColorOption1",
            events: [event("Later", on: 20), event("Earlier", on: 3), event("Middle", on: 11)]
        )

        #expect(batch.events.map(\.name) == ["Earlier", "Middle", "Later"])
    }

    @Test("Batch date is derived from its first event, not stored")
    func batchDateIsDerived() {
        let empty = CalendarEventBatch(name: "Empty")
        #expect(empty.date == nil)
        #expect(empty.isEmpty)

        let batch = CalendarEventBatch(
            name: "B",
            events: [event("Later", on: 20), event("Earlier", on: 3)]
        )
        #expect(batch.date == day(2026, 6, 3))

        // Removing the earliest event must move the derived date with it. This is the
        // drift the old stored `date` property allowed.
        let trimmed = batch.with(events: [event("Later", on: 20)])
        #expect(trimmed.date == day(2026, 6, 20))
    }

    @Test("Batch merge key is the persisted id when present, the pending id otherwise")
    func batchMergeKey() {
        let staged = CalendarEventBatch(name: "B", events: [event(on: 1)])
        #expect(staged.mergeKey == .pending(staged.pendingID))

        let saved = staged.with(persistedID: 42)
        #expect(saved.mergeKey == .persisted(42))
    }

    @Test("Two staged batches with identical content are distinguishable, but recognisable")
    func stagedBatchesAreDistinguishable() {
        let a = CalendarEventBatch(name: "Same", events: [event(on: 1)])
        let b = CalendarEventBatch(name: "Same", events: [event(on: 1)])

        // Identity is part of equality, so two staged batches are never conflated.
        #expect(a != b)
        #expect(a.mergeKey != b.mergeKey)

        // Content equality is the separate question the reload-adoption path asks:
        // "is this the batch I staged, now that it has come back under a real id?"
        #expect(a.hasSameContent(as: b, using: provider))
    }

    @Test("Batch recolours its events by default")
    func batchRecolour() {
        let batch = CalendarEventBatch(
            name: "B",
            colorName: "eventColorOption1",
            events: [event("A", on: 1), event("B", on: 2)]
        )
        let recoloured = batch.with(colorName: "eventColorOption3")

        #expect(recoloured.colorName == "eventColorOption3")
        #expect(recoloured.events.allSatisfy { $0.colorName == "eventColorOption3" })
    }

    @Test("Batch occurs(on:) matches on event days")
    func batchOccurs() {
        let batch = CalendarEventBatch(
            name: "B",
            events: [event("A", on: 3), event("B", on: 17)]
        )

        #expect(batch.occurs(on: day(2026, 6, 17), using: provider))
        #expect(!batch.occurs(on: day(2026, 6, 18), using: provider))
        // Same instant, different time of day: still the same day.
        #expect(batch.occurs(on: day(2026, 6, 17).addingTimeInterval(3600), using: provider))
    }

    @Test("Batch content equality ignores identity and compares days")
    func batchContentEquality() {
        let a = CalendarEventBatch(
            name: "B",
            colorName: "eventColorOption1",
            events: [event("A", on: 3), event("B", on: 17)]
        )
        let bSameContent = a.with(persistedID: 99)
        let cDifferentName = a.with(name: "Other")
        let cDifferentDay = CalendarEventBatch(
            name: "B",
            colorName: "eventColorOption1",
            events: [event("A", on: 3), event("B", on: 18)]
        )
        let cFewer = CalendarEventBatch(
            name: "B",
            colorName: "eventColorOption1",
            events: [event("A", on: 3)]
        )
        let cEmpty = CalendarEventBatch(name: "B", colorName: "eventColorOption1")

        #expect(a.hasSameContent(as: bSameContent, using: provider))
        #expect(!a.hasSameContent(as: cDifferentName, using: provider))
        #expect(!a.hasSameContent(as: cDifferentDay, using: provider))
        #expect(!a.hasSameContent(as: cFewer, using: provider))
        #expect(!cEmpty.hasSameContent(as: cEmpty, using: provider), "an empty batch is never a match")
    }

    // MARK: - PinCalendar

    @Test("Calendar is management data only and carries no event graph")
    func calendarIsMetadataOnly() {
        let calendar = PinCalendar(name: "Work", year: 2026, numberOfColumns: 3)

        #expect(calendar.id == 0)
        #expect(calendar.name == "Work")
        #expect(calendar.year == 2026)
        #expect(calendar.numberOfColumns == 3)
        #expect(!calendar.isArchived)
    }

    @Test("Calendar is mutable, so a rename is a plain assignment")
    func calendarIsMutable() {
        var calendar = PinCalendar(id: 7, name: "Work", year: 2026, numberOfColumns: 3)
        calendar.name = "Renamed"

        #expect(calendar.name == "Renamed")
        #expect(calendar.id == 7)
    }

    @Test("Calendar equality covers every stored field")
    func calendarEquality() {
        let a = PinCalendar(id: 1, name: "Work", year: 2026, numberOfColumns: 3)
        let same = PinCalendar(id: 1, name: "Work", year: 2026, numberOfColumns: 3)

        #expect(a == same)
        #expect(a != PinCalendar(id: 1, name: "Work", year: 2026, numberOfColumns: 6))
        #expect(a != PinCalendar(id: 1, name: "Work", year: 2025, numberOfColumns: 3))
        #expect(a != PinCalendar(id: 1, name: "Other", year: 2026, numberOfColumns: 3))
        #expect(a != PinCalendar(id: 1, name: "Work", year: 2026, numberOfColumns: 3, isArchived: true))
    }

    // MARK: - PCCalendarDataProvider

    @Test("The data provider is the single day-comparison authority")
    func dayComparison() {
        let morning = day(2026, 6, 14)
        let anHourLater = morning.addingTimeInterval(3600)
        let threeDaysLater = morning.addingTimeInterval(3 * 86400)

        #expect(provider.isSameDay(morning, anHourLater))
        #expect(!provider.isSameDay(morning, threeDaysLater))
        #expect(provider.isSameDay(morning, morning))
    }

    @Test("startOfDay is idempotent and never after its input")
    func startOfDay() {
        let evening = day(2026, 6, 14).addingTimeInterval(20 * 3600)
        let start = provider.startOfDay(for: evening)

        #expect(start <= evening)
        #expect(provider.startOfDay(for: start) == start)
    }

    @Test("The provider reports the same components a gregorian calendar does")
    func providerComponents() {
        let date = day(2026, 6, 14)

        // Note: `PCCalendarDataProvider.init` overwrites the calendar's time zone and
        // locale with the current ones, so a caller cannot pin them. Assert against
        // the provider's own answers rather than a separately-built calendar.
        #expect(provider.month(of: date) == provider.dateComponents(forDate: date).month)
        #expect(provider.year(of: date) == provider.dateComponents(forDate: date).year)
    }

    @Test("Two providers built the same way are equal, so it can live in Equatable state")
    func providerEquality() {
        #expect(PCCalendarDataProvider() == PCCalendarDataProvider())
    }
}
