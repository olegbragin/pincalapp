import Foundation
import Testing
import CorePersistence
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventBatchViewModel Tests")
struct AddEditEventBatchViewModelTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    @Test("init prepares the event list and calendar")
    func initPrepares() {
        let date = day(2026, 6, 1)
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: date, color: "eventColorOption1")
        ])

        #expect(vm.addEditListViewModel.events.count == 1)
        #expect(vm.yearModel.months.count == 12)
        #expect(vm.yearModel.numberOfCurrentMonth > 0)
    }

    @Test("canSave requires a name and a color")
    func canSaveRequirements() {
        let vm = AddEditEventBatchViewModel()
        #expect(!vm.canSave)

        vm.eventBatchName = "Summer"
        #expect(!vm.canSave)

        vm.selectedColor = .option1
        #expect(vm.canSave)
    }

    @Test("save returns false when invalid")
    func saveIsInvalid() {
        let vm = AddEditEventBatchViewModel()

        #expect(vm.save() == false)
        #expect(vm.eventBatch == nil)
    }

    @Test("save builds an event batch from current fields")
    func saveBuildsBatch() {
        let date = day(2026, 6, 1)
        let storedEvent = EventDataSource(name: "Swim", date: date, color: "eventColorOption1")
        let vm = AddEditEventBatchViewModel(events: [storedEvent])
        vm.eventBatchId = 7
        vm.eventBatchName = "Beach"
        vm.selectedColor = .option2
        vm.date = date
        let timestampToUse = UUID()
        vm.timestamp = timestampToUse

        #expect(vm.save() == true)

        #expect(vm.eventBatch != nil)
        #expect(vm.eventBatch?.id == 7)
        #expect(vm.eventBatch?.name == "Beach")
        #expect(vm.eventBatch?.colorName == PCColorOption.option2.colorName)
        #expect(vm.eventBatch?.events == [storedEvent])
        #expect(vm.eventBatch?.date == date)
        #expect(vm.eventBatch?.timestamp == timestampToUse)
    }

    @Test("defaultColor falls back to the first event color")
    func defaultColorFallback() {
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: PCColorOption.option3.colorName)
        ])

        #expect(vm.defaultColor == .option3)
    }

    @Test("toggleEvent adds and removes an event for the tapped day")
    func toggleEvent() {
        let date = day(2026, 6, 1)
        let vm = AddEditEventBatchViewModel()
        vm.eventBatchName = "Trip"
        vm.selectedColor = .option2

        vm.toggleEvent(on: date)

        #expect(vm.addEditListViewModel.events.count == 1)
        #expect(vm.addEditListViewModel.events.first?.name == "Trip")
        #expect(vm.addEditListViewModel.events.first?.color == PCColorOption.option2.colorName)
        #expect(vm.daySelectionManager.selectedDays.isEmpty)

        vm.toggleEvent(on: date)

        #expect(vm.addEditListViewModel.events.isEmpty)
    }

    @Test("recolorAllEvents applies the selected color to all events")
    func recolorAllEvents() {
        let date = day(2026, 6, 1)
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: date, color: "eventColorOption1")
        ])
        vm.selectedColor = .option4

        vm.recolorAllEvents()

        #expect(vm.addEditListViewModel.events.allSatisfy { $0.color == PCColorOption.option4.colorName })
    }

    @Test("preferredTitle formats a single date")
    func preferredTitleSingleDate() {
        let vm = AddEditEventBatchViewModel()
        vm.date = day(2026, 6, 1)

        #expect(vm.preferredTitle != nil)
        #expect(vm.preferredTitle?.contains("2026") == true)
        #expect(vm.preferredTitle?.contains(" - ") == false)
    }

    @Test("preferredTitle formats a range of dates")
    func preferredTitleRange() {
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1"),
            EventDataSource(name: "B", date: day(2026, 6, 10), color: "eventColorOption1")
        ])

        #expect(vm.preferredTitle?.contains("2026") == true)
        #expect(vm.preferredTitle?.contains(" - ") == true)
    }

    @Test("compactTitle is produced for a numeric date")
    func compactTitle() {
        let date = day(2026, 6, 1)
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: date, color: "eventColorOption1")
        ])

        #expect(vm.compactTitle != nil)
        #expect(vm.compactTitle?.isEmpty == false)
    }

    @Test("titles are nil without events or a date")
    func titlesNilWithoutContent() {
        let vm = AddEditEventBatchViewModel()

        #expect(vm.preferredTitle == nil)
        #expect(vm.compactTitle == nil)
    }

    @Test("prepare replaces the event list and rebuilds the calendar")
    func prepareReplacesEvents() {
        let newDate = day(2027, 6, 1)
        let replacement = [EventDataSource(name: "B", date: newDate, color: "eventColorOption2")]
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")
        ])

        vm.prepare(with: replacement)

        #expect(vm.addEditListViewModel.events.map(\.name) == ["B"])
        #expect(vm.addEditListViewModel.events.first?.date == newDate)
        #expect(vm.yearModel.months.count == 12)
    }

    @Test("reset clears editor state")
    func resetClears() {
        let vm = AddEditEventBatchViewModel(events: [
            EventDataSource(name: "A", date: day(2026, 6, 1), color: "eventColorOption1")
        ])
        vm.eventBatchName = "X"
        vm.selectedColor = .option1

        vm.reset()

        #expect(vm.eventBatchName == "")
        #expect(vm.selectedColor == nil)
        #expect(vm.date == nil)
        #expect(vm.timestamp == nil)
        #expect(vm.eventBatch == nil)
        #expect(vm.selectedDays.isEmpty)
        #expect(vm.yearModel.months.isEmpty)
    }
}