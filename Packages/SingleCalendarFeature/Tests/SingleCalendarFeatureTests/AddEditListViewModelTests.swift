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

    @Test("prepare sorts events by date and stamps timestamps")
    func prepareSortsAndStampsTimestamps() {
        let later = EventDataSource(
            name: "Later",
            date: day(2026, 6, 2),
            color: "eventColorOption1"
        )
        let earlier = EventDataSource(
            name: "Earlier",
            date: day(2026, 6, 1),
            color: "eventColorOption1"
        )
        let vm = AddEditListViewModel(events: [later, earlier])

        vm.prepare(with: [later, earlier])

        #expect(vm.events.map(\.name) == ["Earlier", "Later"])
        #expect(vm.events.allSatisfy { $0.timestamp != nil })
    }

    @Test("prepare preserves an existing timestamp")
    func preparePreservesTimestamp() {
        let ts = UUID()
        let stamped = EventDataSource(
            id: 1,
            name: "A",
            date: day(2026, 6, 1),
            color: "eventColorOption1",
            timestamp: ts
        )
        let vm = AddEditListViewModel(events: [stamped])

        vm.prepare(with: [stamped])

        #expect(vm.events.first?.timestamp == ts)
    }

    @Test("apply appends a new event and notifies")
    func applyAppendsAndNotifies() {
        var changeCount = 0
        let vm = AddEditListViewModel()
        vm.onEventsChanged = { changeCount += 1 }
        let event = EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")

        vm.apply(with: event)

        #expect(vm.events == [event])
        #expect(changeCount == 1)
    }

    @Test("apply replaces an event with a matching timestamp")
    func applyReplacesByTimestamp() {
        let ts = UUID()
        let vm = AddEditListViewModel(events: [
            EventDataSource(id: 0, name: "Old", date: day(2026, 6, 1), color: "eventColorOption1", timestamp: ts)
        ])
        let updated = EventDataSource(id: 0, name: "New", date: day(2026, 6, 1), color: "eventColorOption2", timestamp: ts)

        vm.apply(with: updated)

        #expect(vm.events.count == 1)
        #expect(vm.events.first?.name == "New")
        #expect(vm.events.first?.color == "eventColorOption2")
    }

    @Test("apply replaces an event by id when timestamps differ")
    func applyReplacesById() {
        let vm = AddEditListViewModel(events: [
            EventDataSource(id: 3, name: "Old", date: day(2026, 6, 1), color: "eventColorOption1", timestamp: UUID())
        ])
        let updated = EventDataSource(id: 3, name: "New", date: day(2026, 6, 2), color: "eventColorOption1", timestamp: UUID())

        vm.apply(with: updated)

        #expect(vm.events.count == 1)
        #expect(vm.events.first?.name == "New")
        #expect(vm.events.first?.date == day(2026, 6, 2))
    }

    @Test("addEvent appends with a timestamp and keeps sorting")
    func addEventAppendsSorted() {
        let vm = AddEditListViewModel(events: [
            EventDataSource(name: "Later", date: day(2026, 6, 2), color: "eventColorOption1")
        ])

        vm.addEvent(EventDataSource(name: "Earlier", date: day(2026, 6, 1), color: "eventColorOption1"))

        #expect(vm.events.map(\.name) == ["Earlier", "Later"])
        #expect(vm.events[0].timestamp != nil)
    }

    @Test("removeEvent removes all events on the same day")
    func removeEventOnDay() {
        let vm = AddEditListViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")
        ])

        vm.removeEvent(on: day(2026, 6, 1))

        #expect(vm.events.isEmpty)
    }

    @Test("removeEvents removes events by index and notifies")
    func removeEventsByIndexSet() {
        var changeCount = 0
        let vm = AddEditListViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1"),
            EventDataSource(name: "B", date: day(2026, 6, 2), color: "eventColorOption1"),
            EventDataSource(name: "C", date: day(2026, 6, 3), color: "eventColorOption1")
        ])
        vm.onEventsChanged = { changeCount += 1 }

        vm.removeEvents(at: IndexSet(integer: 1))

        #expect(vm.events.map(\.name) == ["A", "C"])
        #expect(changeCount == 1)

        vm.removeEvents(at: IndexSet(integer: 0))

        #expect(vm.events.map(\.name) == ["C"])
    }

    @Test("hasEvent reports presence on the same calendar day")
    func hasEventOnDay() {
        let vm = AddEditListViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")
        ])

        #expect(vm.hasEvent(on: day(2026, 6, 1)))
        #expect(!vm.hasEvent(on: day(2026, 6, 2)))
    }

    @Test("recolorAll changes every event color")
    func recolorAll() {
        let vm = AddEditListViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")
        ])

        vm.recolorAll(to: "eventColorOption4")

        #expect(vm.events.allSatisfy { $0.color == "eventColorOption4" })
    }

    @Test("commitPendingEventIfNeeded applies a saved pending event once")
    func commitPendingEventOnce() {
        let vm = AddEditListViewModel()
        let editor = vm.addEditEventModel
        editor.eventName = "Planned"
        editor.selectedColor = .option3
        editor.selectedDate = day(2026, 6, 1)
        #expect(editor.save())

        #expect(vm.commitPendingEventIfNeeded() == true)
        #expect(vm.events.count == 1)
        #expect(vm.events.first?.name == "Planned")
        #expect(vm.commitPendingEventIfNeeded() == false)
        #expect(vm.events.count == 1)
    }

    @Test("reset clears events and editor state")
    func resetClears() {
        let vm = AddEditListViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")
        ])
        vm.prepareAddEditViewModel(with: EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1"))

        vm.reset()

        #expect(vm.events.isEmpty)
        #expect(vm.selectedDay == nil)
    }
}