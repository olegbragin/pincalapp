import Foundation
import Testing
import CorePersistence
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditListViewModel Tests")
struct AddEditListViewModelTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func event(
        _ name: String = "Event",
        day dayOfMonth: Int,
        color: String = "eventColorOption1",
        timestamp: UUID? = nil
    ) -> EventDataSource {
        .init(name: name, date: day(2026, 6, dayOfMonth), color: color, timestamp: timestamp)
    }

    // MARK: - init / state

    @Test("init defaults to an empty list")
    func initIsEmpty() {
        let vm = AddEditListViewModel()
        #expect(vm.events.isEmpty)
        #expect(vm.selectedDay == nil)
    }

    @Test("init keeps the provided events")
    func initKeepsEvents() {
        let vm = AddEditListViewModel(events: [event("A", day: 1)])
        #expect(vm.events == [event("A", day: 1)])
    }

    // MARK: - prepare

    @Test("prepare sorts events by date and stamps missing timestamps")
    func prepareSortsAndStampsTimestamps() {
        let later = event("Later", day: 2)
        let earlier = event("Earlier", day: 1)
        let vm = AddEditListViewModel(events: [later, earlier])

        vm.prepare(with: [later, earlier])

        #expect(vm.events.map(\.name) == ["Earlier", "Later"])
        #expect(vm.events.allSatisfy { $0.timestamp != nil })
        #expect(vm.events[0].timestamp != vm.events[1].timestamp)
    }

    @Test("prepare preserves an existing timestamp")
    func preparePreservesTimestamp() {
        let ts = UUID()
        let vm = AddEditListViewModel(events: [event(day: 1, timestamp: ts)])

        vm.prepare(with: [event(day: 1, timestamp: ts)])

        #expect(vm.events.first?.timestamp == ts)
    }

    @Test("prepare replaces the list, not mutating the input ordering")
    func prepareReplacesList() {
        let a = event("A", day: 1)
        let b = event("B", day: 2)
        let vm = AddEditListViewModel(events: [])

        vm.prepare(with: [b, a])

        #expect(vm.events.map(\.name) == ["A", "B"])
    }

    // MARK: - apply

    @Test("apply appends when nothing matches and notifies")
    func applyAppendsAndNotifies() {
        var changeCount = 0
        let vm = AddEditListViewModel()
        vm.onEventsChanged = { changeCount += 1 }
        let newEvent = event("A", day: 1)

        vm.apply(with: newEvent)

        #expect(vm.events == [newEvent])
        #expect(changeCount == 1)
    }

    @Test("apply replaces an event with a matching timestamp")
    func applyReplacesByTimestamp() {
        let ts = UUID()
        let vm = AddEditListViewModel(events: [event("Old", day: 1, timestamp: ts)])
        let updated = event("New", day: 2, color: "eventColorOption3", timestamp: ts)

        vm.apply(with: updated)

        #expect(vm.events.count == 1)
        #expect(vm.events.first?.name == "New")
        #expect(vm.events.first?.color == "eventColorOption3")
        #expect(vm.events.first?.date == day(2026, 6, 2))
    }

    @Test("apply replaces an event by id when timestamps differ")
    func applyReplacesById() {
        let stored = EventDataSource(id: 5, name: "Old", date: day(2026, 6, 1), color: "eventColorOption1", timestamp: UUID())
        let vm = AddEditListViewModel(events: [stored])
        let updated = EventDataSource(id: 5, name: "New", date: day(2026, 6, 2), color: "eventColorOption2", timestamp: UUID())

        vm.apply(with: updated)

        #expect(vm.events.count == 1)
        #expect(vm.events.first?.name == "New")
        #expect(vm.events.first?.date == day(2026, 6, 2))
        #expect(vm.events.first?.color == "eventColorOption2")
    }

    @Test("apply prefers a timestamp match over an id match")
    func applyPrefersTimestampMatch() {
        let tsA = UUID()
        let vm = AddEditListViewModel(events: [
            event("A", day: 1, timestamp: tsA),
            event("B", day: 2, timestamp: UUID())
        ])
        // New event carries B's id but A's timestamp.
        let bId = vm.events[1].id
        let updated = EventDataSource(id: bId, name: "Edited", date: day(2026, 6, 3), color: "eventColorOption1", timestamp: tsA)

        vm.apply(with: updated)

        // The timestamp match (event A) wins, so the *first* row is replaced.
        #expect(vm.events[0].name == "Edited")
        #expect(vm.events.count == 2)
        #expect(vm.events[1].name == "B")
    }

    // MARK: - addEvent

    @Test("addEvent appends with a timestamp and keeps sorting")
    func addEventAppendsSorted() {
        let vm = AddEditListViewModel(events: [event("Later", day: 2)])

        vm.addEvent(event("Earlier", day: 1))

        #expect(vm.events.map(\.name) == ["Earlier", "Later"])
        #expect(vm.events[0].timestamp != nil)
    }

    // MARK: - removal

    @Test("removeEvent removes all events on the same day")
    func removeEventRemovesAllOnDay() {
        let vm = AddEditListViewModel(events: [
            event("A", day: 1, timestamp: UUID()),
            event("A2", day: 1, timestamp: UUID()),
            event("B", day: 2, timestamp: UUID())
        ])

        vm.removeEvent(on: day(2026, 6, 1))

        #expect(vm.events.map(\.name) == ["B"])
    }

    @Test("removeEvents removes events by index and notifies")
    func removeEventsByIndexSet() {
        var changeCount = 0
        let vm = AddEditListViewModel(events: [
            event("A", day: 1),
            event("B", day: 2),
            event("C", day: 3)
        ])
        vm.onEventsChanged = { changeCount += 1 }

        vm.removeEvents(at: IndexSet(integer: 1))

        #expect(vm.events.map(\.name) == ["A", "C"])
        #expect(changeCount == 1)

        vm.removeEvents(at: IndexSet(integer: 0))

        #expect(vm.events.map(\.name) == ["C"])
        #expect(changeCount == 2)
    }

    @Test("removeEvents removes multiple indices at once")
    func removeEventsMultipleIndices() {
        let vm = AddEditListViewModel(events: [
            event("A", day: 1),
            event("B", day: 2),
            event("C", day: 3),
            event("D", day: 4)
        ])

        vm.removeEvents(at: [0, 2])

        #expect(vm.events.map(\.name) == ["B", "D"])
    }

    // MARK: - hasEvent

    @Test("hasEvent reports presence on the same calendar day")
    func hasEventOnDay() {
        let vm = AddEditListViewModel(events: [event("A", day: 1)])

        #expect(vm.hasEvent(on: day(2026, 6, 1)))
        #expect(!vm.hasEvent(on: day(2026, 6, 2)))
    }

    // MARK: - recolorAll

    @Test("recolorAll changes every event color but preserves other fields")
    func recolorAllRecolorsAndPreserves() {
        let vm = AddEditListViewModel(events: [
            event("A", day: 1, color: "eventColorOption1"),
            event("B", day: 2, color: "eventColorOption2")
        ])
        let namesBefore = vm.events.map(\.name)

        vm.recolorAll(to: "eventColorOption4")

        #expect(vm.events.allSatisfy { $0.color == "eventColorOption4" })
        #expect(vm.events.map(\.name) == namesBefore)
    }

    // MARK: - reset

    @Test("reset clears events and selection")
    func resetClears() {
        let vm = AddEditListViewModel(events: [event("A", day: 1)])

        vm.reset()

        #expect(vm.events.isEmpty)
        #expect(vm.selectedDay == nil)
    }

    // MARK: - notifications

    @Test("apply notifies, prepare and addEvent do not")
    func notificationBehaviour() {
        var changeCount = 0
        let vm = AddEditListViewModel()
        vm.onEventsChanged = { changeCount += 1 }

        vm.prepare(with: [event("A", day: 1)])
        #expect(changeCount == 0)

        vm.addEvent(event("B", day: 2))
        #expect(changeCount == 0)

        vm.apply(with: event("C", day: 3))
        #expect(changeCount == 1)
    }
}
