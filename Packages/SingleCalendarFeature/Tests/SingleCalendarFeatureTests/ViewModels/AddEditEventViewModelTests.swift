import Foundation
import Testing
import CorePersistence
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventViewModel Tests")
struct AddEditEventViewModelTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - init / state

    @Test("init starts with empty/reset state")
    func initDefaults() {
        let vm = AddEditEventViewModel()

        #expect(vm.eventId == 0)
        #expect(vm.eventName == "")
        #expect(vm.selectedColor == nil)
        #expect(vm.timestamp == nil)
        #expect(vm.event == nil)
        #expect(vm.selectedDayToShowEvents == nil)
    }

    // MARK: - save

    @Test("save fails without a name")
    func saveRequiresName() {
        let vm = AddEditEventViewModel()
        vm.selectedColor = .option1

        #expect(vm.save() == false)
        #expect(vm.event == nil)
    }

    @Test("save fails without a color")
    func saveRequiresColor() {
        let vm = AddEditEventViewModel()
        vm.eventName = "Event"

        #expect(vm.save() == false)
        #expect(vm.event == nil)
    }

    @Test("save builds an event from the current fields")
    func saveBuildsEvent() {
        let date = day(2026, 6, 1)
        let ts = UUID()
        let vm = AddEditEventViewModel()
        vm.eventId = 5
        vm.eventName = "Party"
        vm.selectedColor = .option2
        vm.selectedDate = date
        vm.timestamp = ts

        #expect(vm.save() == true)

        let event = vm.event
        #expect(event != nil)
        #expect(event?.id == 5)
        #expect(event?.name == "Party")
        #expect(event?.date == date)
        #expect(event?.color == PCColorOption.option2.colorName)
        #expect(event?.timestamp == ts)
    }

    @Test("save keeps a nil timestamp when none was assigned")
    func saveKeepsNilTimestamp() {
        let vm = AddEditEventViewModel()
        vm.eventName = "No Time"
        vm.selectedColor = .option1
        vm.selectedDate = day(2026, 6, 2)

        #expect(vm.save() == true)
        #expect(vm.event?.timestamp == nil)
    }

    @Test("save overwrites any previously committed event")
    func saveOverwritesEvent() {
        let vm = AddEditEventViewModel()
        vm.eventName = "First"
        vm.selectedColor = .option1
        vm.selectedDate = day(2026, 6, 1)
        #expect(vm.save())
        let first = vm.event

        vm.eventName = "Second"
        #expect(vm.save())
        #expect(vm.event != nil)
        #expect(vm.event?.name == "Second")
        #expect(vm.event != first)
    }

    // MARK: - update(from:)

    @Test("update populates the editor from an existing event")
    func updatePopulatesEditor() {
        let date = day(2026, 6, 1)
        let ts = UUID()
        let event = EventDataSource(
            id: 7,
            name: "Hydrate",
            date: date,
            color: PCColorOption.option4.colorName,
            timestamp: ts
        )
        let vm = AddEditEventViewModel()

        vm.update(from: event)

        #expect(vm.eventId == 7)
        #expect(vm.eventName == "Hydrate")
        #expect(vm.selectedColor == .option4)
        #expect(vm.selectedDate == date)
        #expect(vm.timestamp == ts)
        #expect(vm.selectedDayToShowEvents == date)
    }

    @Test("update then save round-trips the event")
    func updateThenSaveRoundTrips() {
        let date = day(2026, 6, 1)
        let ts = UUID()
        let original = EventDataSource(id: 3, name: "Original", date: date, color: PCColorOption.option1.colorName, timestamp: ts)
        let vm = AddEditEventViewModel()

        vm.update(from: original)
        #expect(vm.save())

        let saved = vm.event
        #expect(saved == original)
    }

    // MARK: - reset

    @Test("reset clears all fields")
    func resetClearsFields() {
        let vm = AddEditEventViewModel()
        vm.eventName = "Party"
        vm.selectedColor = .option1
        vm.eventId = 9
        vm.selectedDate = day(2026, 6, 1)
        vm.timestamp = UUID()
        _ = vm.save()

        vm.reset()

        #expect(vm.eventName == "")
        #expect(vm.selectedColor == nil)
        #expect(vm.event == nil)
        #expect(vm.eventId == 0)
        #expect(vm.timestamp == nil)
        #expect(vm.selectedDayToShowEvents == nil)
    }
}
