import Foundation
import Testing
import CorePersistence
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventBatchListViewModel Tests")
struct AddEditEventBatchListViewModelTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func batch(_ id: Int64, _ name: String, on date: Date) -> EventBatchDataSource {
        EventBatchDataSource(
            id: id,
            name: name,
            events: [EventDataSource(name: "E", date: date, color: "eventColorOption1")]
        )
    }

    @Test("prepare sorts batches by earliest event date")
    func prepareSortsByEarliestEvent() {
        let later = batch(2, "Later", on: day(2026, 6, 2))
        let earlier = batch(1, "Earlier", on: day(2026, 6, 1))
        let vm = AddEditEventBatchListViewModel()

        vm.prepare(with: [later, earlier], and: day(2026, 6, 1))

        #expect(vm.eventBatches.map(\.id) == [1, 2])
        #expect(vm.selectedDay == day(2026, 6, 1))
        #expect(vm.isEditing)
    }

    @Test("removeBatches stores removed batches for deletion")
    func removeBatches() {
        let vm = AddEditEventBatchListViewModel()
        vm.prepare(
            with: [batch(1, "A", on: day(2026, 6, 1)), batch(2, "B", on: day(2026, 6, 2))],
            and: day(2026, 6, 1)
        )
        vm.eventBatchesToDelete = []

        vm.removeBatches(at: IndexSet(integer: 0))

        #expect(vm.eventBatches.count == 1)
        #expect(vm.eventBatchesToDelete.map(\.id) == [1])
    }

    @Test("commitDelete promotes selected batches to pending deletion")
    func commitDelete() {
        let vm = AddEditEventBatchListViewModel()
        vm.eventBatchesSelectedToDelete = [batch(5, "Five", on: day(2026, 6, 1))]

        vm.commitDelete()

        #expect(vm.eventBatchesToDelete.map(\.id) == [5])
        #expect(vm.eventBatchesSelectedToDelete.isEmpty)
        #expect(!vm.isEditing)
    }

    @Test("cancel resets editing state")
    func cancelResetsEditing() {
        let vm = AddEditEventBatchListViewModel()
        vm.prepare(with: [batch(1, "A", on: day(2026, 6, 1))], and: day(2026, 6, 1))

        vm.cancel()

        #expect(vm.eventBatches.count == 1)
        #expect(vm.eventBatchesSelectedToDelete.isEmpty)
        #expect(!vm.isEditing)
    }

    @Test("batch list and editor stay connected through the shared managers")
    func connectsToEditorViaSharedManagers() {
        let someDay = day(2026, 6, 1)
        let vm = AddEditEventBatchListViewModel()

        // The editor is created with the same manager instances the list owns.
        let editor = AddEditEventBatchViewModel(eventsSelectionManager: vm.eventsSelectionManager)
        editor.load(batch(9, "Existing", on: someDay))

        #expect(editor.eventBatchId == 9)
        #expect(editor.eventBatchName == "Existing")
        #expect(editor.selectedColor != nil)
        #expect(editor.date == nil)
        #expect(editor.eventsSelectionManager.events.count == 1)

        // Mutating the editor's event store is visible through the list's own
        // manager instance — they are the same object, so the two stay in sync.
        editor.eventsSelectionManager.addEvent(
            EventDataSource(name: "Added", date: someDay, color: "eventColorOption1")
        )
        #expect(vm.eventsSelectionManager.events.count == 2)
    }

    @Test("reset clears batches and editor state")
    func resetClears() {
        let someDay = day(2026, 6, 1)
        let vm = AddEditEventBatchListViewModel()
        vm.prepare(with: [batch(1, "A", on: someDay)], and: someDay)
        vm.eventBatchesToDelete = [batch(2, "B", on: someDay)]

        vm.reset()

        #expect(vm.eventBatches.isEmpty)
        #expect(vm.eventBatchesSelectedToDelete.isEmpty)
        #expect(vm.selectedDay == someDay)
        #expect(!vm.isEditing)
    }

    @Test("eventsForDay filters and sorts events on the given day")
    func eventsForDay() {
        let base = day(2026, 6, 1)
        let calendar = Calendar.autoupdatingCurrent
        let earlyDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)!
        let lateDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: base)!
        let otherDay = day(2026, 6, 3)
        let earlyEvent = EventDataSource(id: 1, name: "Early", date: earlyDate, color: "eventColorOption1")
        let lateEvent = EventDataSource(id: 2, name: "Late", date: lateDate, color: "eventColorOption1")
        let batch = EventBatchDataSource(id: 1, name: "Mixed", events: [lateEvent, earlyEvent])

        #expect(batch.eventsForDay(base).map(\.id) == [1, 2])
        #expect(batch.eventsForDay(otherDay).isEmpty)
        #expect(batch.eventsForDay(nil).map(\.id) == [1, 2])
    }
}