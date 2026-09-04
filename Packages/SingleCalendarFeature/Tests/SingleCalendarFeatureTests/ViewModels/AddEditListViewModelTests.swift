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
    }

    @Test("prepare preserves an existing timestamp")
    func preparePreservesTimestamp() {
        let ts = UUID()
        let vm = AddEditListViewModel(events: [event(day: 1, timestamp: ts)])

        vm.prepare(with: [event(day: 1, timestamp: ts)])

        #expect(vm.events.first?.timestamp == ts)
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

    // MARK: - addEvent / removal

    @Test("addEvent appends with a timestamp and keeps sorting")
    func addEventAppendsSorted() {
        let vm = AddEditListViewModel(events: [event("Later", day: 2)])

        vm.addEvent(event("Earlier", day: 1))

        #expect(vm.events.map(\.name) == ["Earlier", "Later"])
        #expect(vm.events[0].timestamp != nil)
    }

    @Test("removeEvent removes all events on the same day")
    func removeEventOnDay() {
        let vm = AddEditListViewModel(events: [event("A", day: 1), event("B", day: 2)])

        vm.removeEvent(on: day(2026, 6, 1))

        #expect(vm.events.map(\.name) == ["B"])
    }

    @Test("removeEvents removes by index and notifies")
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
    }

    // MARK: - queries / other

    @Test("hasEvent reports presence on the same calendar day")
    func hasEventOnDay() {
        let vm = AddEditListViewModel(events: [event("A", day: 1)])

        #expect(vm.hasEvent(on: day(2026, 6, 1)))
        #expect(!vm.hasEvent(on: day(2026, 6, 2)))
    }

    @Test("recolorAll changes every event color")
    func recolorAll() {
        let vm = AddEditListViewModel(events: [event("A", day: 1)])

        vm.recolorAll(to: "eventColorOption4")

        #expect(vm.events.allSatisfy { $0.color == "eventColorOption4" })
    }

    @Test("reset clears events and selection")
    func resetClears() {
        let vm = AddEditListViewModel(events: [event("A", day: 1)])

        vm.reset()

        #expect(vm.events.isEmpty)
        #expect(vm.selectedDay == nil)
    }
}
