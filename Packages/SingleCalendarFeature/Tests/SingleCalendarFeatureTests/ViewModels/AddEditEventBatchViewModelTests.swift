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

    /// Colour is what `canSave` reads. The name deliberately is not: a batch is a set of
    /// dated, coloured events, so clearing the title does not make it any less one, and
    /// refusing to save it would leave the store ahead of the database with nowhere to put
    /// the work.
    @Test("canSave needs a colour, and does not care about the name")
    func canSaveRequirements() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(vm.canSave, "a new batch arrives ready to save")
        store.send(.setBatchName(""))
        #expect(vm.canSave, "a nameless batch is still a batch")
        store.send(.setBatchName("Morning"))
        #expect(vm.canSave)
        store.send(.setBatchColor(nil))
        #expect(!vm.canSave, "no colour is the one thing that stops a write")
        store.send(.setBatchColor(PCColorOption.firstAvailable))
        #expect(vm.canSave)
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

    /// An uncoloured batch cannot be written, and Save must not pretend otherwise.
    ///
    /// The batch is already in the store — `startNewBatch` writes it — so this cannot assert
    /// an empty registry any more. What it can still pin is that Save on an uncoloured batch
    /// writes no *further* row and does not leave the editor, which is the guard that matters:
    /// a batch with no colour has no row to save.
    @Test("Saving an uncoloured batch writes nothing further")
    func saveIsGuarded() async {
        let (vm, store, persistence) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        // Colour is what has to go — the name stopped being a precondition, so clearing it
        // would no longer produce an unsavable batch to test the guard with.
        // Settle the writes from creating the batch before counting, or the count races the
        // chain rather than measuring the save.
        _ = await persistence.waitForWrites(2)
        let writesBefore = await persistence.writes.count

        store.send(.setBatchColor(nil))
        #expect(!vm.canSave, "precondition: the batch really is unsavable")

        vm.save()

        #expect(await persistence.writes.count == writesBefore,
                "an uncoloured batch resolves to no row, so there is nothing further to write")
        #expect(store.state.stage == .batchEditor, "and the editor stays open")
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
