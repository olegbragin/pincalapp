//
//  AddEditEventViewModelTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 15.03.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventViewModel")
struct AddEditEventViewModelTests {

    private func makeContext() -> (AddEditEventViewModel, PCEventSelectionManager) {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.openEvent(pendingID: store.state.assembly!.batch.events[0].pendingID))
        return (AddEditEventViewModel(store: store), store)
    }

    @Test("With no draft, the name is empty and it cannot be saved")
    func noDraft() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        let vm = AddEditEventViewModel(store: store)

        #expect(vm.nameBinding.wrappedValue.isEmpty)
        #expect(!vm.canSave)
    }

    /// §12.4: projections track `state.eventDraft`, and `save()` dispatches
    /// `saveEventTapped`. The old version kept its own mutable `event`, so these
    /// assertions are about the *store* moving rather than a local field.
    @Test("The name binding dispatches to the draft")
    func nameBindingDispatches() {
        let (vm, store) = makeContext()

        vm.nameBinding.wrappedValue = "Swim"

        #expect(store.state.eventDraft?.name == "Swim")
        #expect(vm.nameBinding.wrappedValue == "Swim")
    }

    @Test("The colour binding dispatches a colour option")
    func colorBindingDispatches() {
        let (vm, store) = makeContext()

        vm.colorBinding.wrappedValue = .option2

        #expect(store.state.eventDraft?.colorName == "eventColorOption2")
        #expect(vm.colorBinding.wrappedValue == .option2)
    }

    @Test("The date binding dispatches the event's date")
    func dateBindingDispatches() {
        let (vm, store) = makeContext()
        let newDate = Fixture.day(4).addingTimeInterval(3600 * 19)

        vm.dateBinding.wrappedValue = newDate

        #expect(store.state.eventDraft?.date == newDate)
    }

    /// A new event arrives named and coloured (§5.4), so this walks the draft *down*:
    /// clearing the colour alone is not enough to refuse a save, and clearing both is.
    @Test("canSave refuses a draft whose name or colour has been cleared")
    func canSaveRequirements() {
        let (vm, _) = makeContext()

        #expect(vm.canSave, "the event arrives named and coloured")
        vm.colorBinding.wrappedValue = nil
        #expect(!vm.canSave, "no colour of its own")
        vm.colorBinding.wrappedValue = .option1
        vm.nameBinding.wrappedValue = ""
        #expect(!vm.canSave, "and no name")
        vm.nameBinding.wrappedValue = "Swim"
        #expect(vm.canSave)
    }

    @Test("The title date is the draft's, falling back to the assembly's day")
    func displayedDate() {
        let (vm, store) = makeContext()
        let draftDate = store.state.eventDraft!.date
        #expect(vm.displayedDate == draftDate)

        // Dropping the draft must not leave the title empty.
        store.send(.discardEventTapped)
        #expect(vm.displayedDate == Fixture.day(4), "falls back to the anchor day")
    }

    @Test("Saving commits the draft into the batch and asks for the pop")
    func saveCommits() {
        let (vm, store) = makeContext()
        vm.nameBinding.wrappedValue = "Swim"
        vm.colorBinding.wrappedValue = .option2

        vm.save()

        #expect(store.state.eventDraft == nil, "the draft is done")
        #expect(store.state.stage == .batchEditor)
        #expect(store.state.assembly?.batch.events.first?.name == "Swim")
        #expect(store.state.assembly?.batch.events.first?.colorName == "eventColorOption2")
        #expect(store.state.navigationRequest?.target == .pop)
    }

    /// A *cleared* name is declined, and the draft survives.
    ///
    /// This used to be about the everyday case — a placeholder event had an empty name, so
    /// opening one and pressing Save was rejected. Placeholders now arrive named (§5.4) and
    /// save, so the guard has one job left and this pins it: a name the user emptied is a
    /// dismissal, not a save, and must not silently drop the edit.
    @Test("Saving an event whose name was cleared is declined, and the draft survives")
    func saveIsGuarded() {
        let (vm, store) = makeContext()
        store.send(.setEventName(""))
        let before = store.state.eventDraft
        #expect(before?.name.isEmpty == true, "precondition: the draft really is unnamed")

        vm.save()

        #expect(store.state.eventDraft == before, "a dismissal, not a silent drop")
        #expect(store.state.stage == .eventEditor(batchPendingID: store.state.assembly!.batch.pendingID, eventPendingID: before!.pendingID))
    }

    /// The complement: a placeholder's default name is a name, so it saves.
    @Test("A new event saves on its default name without the user typing")
    func saveWorksOnTheDefaultName() {
        let (vm, store) = makeContext()
        #expect(vm.canSave, "the event arrives named and coloured")
        let eventName = store.state.eventDraft?.name
        #expect(eventName?.isEmpty == false, "precondition: the draft has a name")

        vm.save()

        #expect(store.state.eventDraft == nil, "committed")
        #expect(store.state.stage == .batchEditor)
        #expect(store.state.assembly?.batch.events.contains { $0.name == eventName } == true)
    }
}
