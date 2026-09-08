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
        vm.eventName = "Swim"
        vm.selectedColor = .option2
        vm.event.date = date

        #expect(vm.save() == true)
        #expect(vm.event.name == "Swim")
        #expect(vm.event.color == PCColorOption.option2.colorName)
        #expect(vm.event.date == date)
    }

    @Test("reset clears all fields")
    func resetClearsFields() {
        let vm = AddEditEventViewModel()
        vm.eventName = "Event"
        vm.selectedColor = .option1

        vm.reset()

        #expect(vm.eventName == "")
        #expect(vm.selectedColor == nil)
    }
}
