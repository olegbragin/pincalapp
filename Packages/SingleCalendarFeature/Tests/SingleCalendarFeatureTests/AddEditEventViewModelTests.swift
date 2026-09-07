import Foundation
import Testing
import DSKit
import CoreDomain
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventViewModel Tests")
struct AddEditEventViewModelTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    @Test("save fails without a name")
    func saveRequiresName() {
        let vm = AddEditEventViewModel()
        vm.selectedColor = .option1

        #expect(vm.save() == false)
        #expect(vm.event.name.isEmpty)
    }

    @Test("save fails without a color")
    func saveRequiresColor() {
        let vm = AddEditEventViewModel()
        vm.eventName = "Event"

        #expect(vm.save() == false)
        #expect(vm.event.color.isEmpty)
    }

    @Test("save builds an event from current fields")
    func saveBuildsEvent() {
        let date = day(2026, 6, 1)
        let vm = AddEditEventViewModel()
        vm.eventId = 5
        vm.eventName = "Party"
        vm.selectedColor = .option2
        vm.selectedDate = date
        vm.timestamp = UUID()

        #expect(vm.save() == true)

        let event = vm.event
        #expect(event.id == 5)
        #expect(event.name == "Party")
        #expect(event.date == date)
        #expect(event.color == PCColorOption.option2.colorName)
        #expect(event.timestamp != nil)
    }

    @Test("reset clears all fields")
    func resetClearsFields() {
        let vm = AddEditEventViewModel()
        vm.eventName = "Party"
        vm.selectedColor = .option1
        _ = vm.save()

        vm.reset()

        #expect(vm.eventName == "")
        #expect(vm.selectedColor == nil)
        #expect(vm.event.id == 0)
        #expect(vm.eventId == 0)
        #expect(vm.timestamp == nil)
    }
}