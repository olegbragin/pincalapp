//
//  AddEditEventBatchViewModelTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 02.07.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// The view model is a projection facade, so these tests are really about two things:
/// that it reports what the store says, and that its commands *dispatch* rather than
/// assign. The second is the point of the rewrite — the previous version had settable
/// `eventBatchId`/`eventBatchName` fields, so a test could set them and assert they stuck
/// without ever involving the batch.
@MainActor
@Suite("AddEditEventBatchViewModel")
struct AddEditEventBatchViewModelTests {

    private func makeContext(
        batches: [CalendarEventBatch] = []
    ) -> (AddEditEventBatchViewModel, PCEventSelectionManager, InMemoryCalendarPersisting) {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(batches: batches, persistence: persistence)
        return (AddEditEventBatchViewModel(store: store), store, persistence)
    }

    @Test("With no assembly, every projection is empty and it cannot be saved")
    func emptyWithoutAssembly() {
        let (vm, _, _) = makeContext()

        #expect(vm.name.isEmpty)
        #expect(vm.events.isEmpty)
        #expect(vm.defaultColor == nil)
        #expect(!vm.canSave)
    }

    @Test("Starting a batch makes the editor show it")
    func reflectsTheStore() {
        let (vm, store, _) = makeContext()

        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(vm.events.count == 1, "one placeholder day")
        #expect(vm.events.first?.date == store.state.dataProvider.startOfDay(for: Fixture.day(4)))
        #expect(vm.canSave, "a new batch arrives named and coloured, so it is savable at once")
    }

    /// The name and the colour are what `canSave` reads, and clearing either one still
    /// refuses the save. What changed is the *starting point*: a new batch arrives with
    /// both already set (§5.4), so this walks the batch back down rather than up.
    @Test("canSave refuses a batch whose name or colour has been cleared")
    func canSaveRequirements() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(vm.canSave, "a new batch arrives ready to save")
        store.send(.setBatchName(""))
        #expect(!vm.canSave, "no name")
        store.send(.setBatchName("Morning"))
        #expect(vm.canSave)
        store.send(.setBatchColor(nil))
        #expect(!vm.canSave, "no colour")
    }

    @Test("A recolour to nil clears the colour and makes the batch unsavable again")
    func recolouringNilClears() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.setBatchName("Morning"))
        store.send(.setBatchColor(.option1))
        #expect(vm.defaultColor == .option1)

        store.send(.setBatchColor(nil))

        #expect(vm.defaultColor == nil)
        #expect(!vm.canSave)
    }

    @Test("The name binding dispatches; it does not assign")
    func nameBindingDispatches() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        vm.nameBinding.wrappedValue = "Evening"

        #expect(store.state.assembly?.batch.name == "Evening", "the store moved, not a local field")
        #expect(vm.name == "Evening", "and the projection follows it")
    }

    @Test("The colour binding dispatches a colour option")
    func colorBindingDispatches() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        vm.colorBinding.wrappedValue = .option3

        #expect(store.state.assembly?.batch.colorName == "eventColorOption3")
        #expect(vm.defaultColor == .option3)
    }

    @Test("A colourless batch's default colour is nil, not a guess")
    func defaultColourIsNilWhenThereIsNothingToFallBackTo() {
        // `recoloring(nil)` clears the batch *and* every event's colour, so there is
        // nothing left to infer. Inventing a colour here would put a swatch on screen that
        // contradicts the batch.
        //
        // The colour has to be cleared explicitly: a new batch now *arrives* coloured
        // (§5.4), so a colourless batch is a state the user reaches rather than the one
        // they start in.
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        #expect(vm.defaultColor != nil, "precondition: a new batch arrives coloured")
        store.send(.setBatchColor(nil))

        #expect(vm.defaultColor == nil)
        #expect(!vm.canSave, "and an uncoloured batch is not savable")
    }

    @Test("Saving an unsavable batch writes nothing")
    func saveIsGuarded() async {
        let (vm, store, persistence) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        // The name is what has to go, since a new batch is otherwise already savable.
        store.send(.setBatchName(""))
        #expect(!vm.canSave, "precondition: the batch really is unsavable")
        let writesBefore = await persistence.writes.count

        vm.save()

        #expect(store.state.batches.isEmpty, "nothing was committed")
        #expect(await persistence.writes.count == writesBefore, "and nothing was written")
    }

    @Test("Saving a valid batch commits it to the registry")
    func saveCommits() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.setBatchName("Morning"))
        store.send(.setBatchColor(.option1))

        vm.save()

        #expect(store.state.batches.count == 1)
        #expect(store.state.batches.first?.name == "Morning")
        #expect(store.state.assembly == nil, "the assembly has left the line")
    }

    @Test("Titles describe the batch's day span")
    func titles() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.toggleDay(Fixture.day(5)))

        #expect(vm.preferredTitle != nil)
        #expect(vm.compactTitle != nil)
        // Two days, so the preferred title is a range rather than one date.
        #expect(vm.preferredTitle?.contains("-") == true, "\(vm.preferredTitle ?? "nil")")
    }

    @Test("A single-day batch's title is a date, not a range")
    func singleDayTitle() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(vm.preferredTitle?.contains("-") == false, "\(vm.preferredTitle ?? "nil")")
    }

    @Test("The year model is the store's, not a copy")
    func yearModelIsTheStores() {
        let (vm, store, _) = makeContext()
        #expect(vm.yearModel === store.yearModel)
    }
}
