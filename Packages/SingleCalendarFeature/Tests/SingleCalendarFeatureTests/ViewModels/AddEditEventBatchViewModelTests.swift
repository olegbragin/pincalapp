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

    @Test("With no assembly, every projection is empty")
    func emptyWithoutAssembly() {
        let (vm, store, _) = makeContext()

        #expect(vm.name.isEmpty)
        #expect(vm.events.isEmpty)
        #expect(vm.defaultColor == nil)
        #expect(store.state.assembly == nil, "precondition: nothing is being edited")
    }

    @Test("Starting a batch makes the editor show it")
    func reflectsTheStore() {
        let (vm, store, _) = makeContext()

        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(vm.events.count == 1, "one placeholder day")
        #expect(vm.events.first?.date == store.state.dataProvider.startOfDay(for: Fixture.day(4)))
        #expect(store.state.assembly?.canSave == true, "a new batch arrives named and coloured, so it is written at once")
    }

    /// Colour is what `PCEventBatchAssembleUnitOfWork.canSave` reads. The name deliberately is
    /// not: a batch is a set of dated, coloured events, so clearing the title does not make it
    /// any less one, and refusing to write it would leave the store ahead of the database with
    /// nowhere to put the work.
    ///
    /// Asserted on the assembly rather than on `AddEditEventBatchViewModel.canSave`, which is
    /// gone with the checkmark it fed. A projection nothing renders is a projection that can
    /// drift from the domain without anything noticing — which is how `canSave` came to need a
    /// test of its own in the first place.
    @Test("A batch needs a colour to be written, and does not care about the name")
    func writableRequirements() {
        let (_, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(store.state.assembly?.canSave == true, "a new batch arrives ready to write")
        store.send(.setBatchName(""))
        #expect(store.state.assembly?.canSave == true, "a nameless batch is still a batch")
        store.send(.setBatchName("Morning"))
        #expect(store.state.assembly?.canSave == true)
        store.send(.setBatchColor(nil))
        #expect(store.state.assembly?.canSave == false, "no colour is the one thing that stops a write")
        store.send(.setBatchColor(PCColorOption.firstAvailable))
        #expect(store.state.assembly?.canSave == true)
    }

    @Test("A recolour to nil clears the colour and makes the batch unwritable again")
    func recolouringNilClears() {
        let (vm, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.setBatchName("Morning"))
        store.send(.setBatchColor(.option1))
        #expect(vm.defaultColor == .option1)

        store.send(.setBatchColor(nil))

        #expect(vm.defaultColor == nil)
        #expect(store.state.assembly?.canSave == false)
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
        #expect(store.state.assembly?.canSave == false, "and an uncoloured batch is not written")
    }

    /// An uncoloured batch has no row to write, and clearing the colour must not pretend
    /// otherwise.
    ///
    /// **Premise changed.** This used to assert that *Save* on an uncoloured batch wrote
    /// nothing and left the editor open — the checkmark's `isEnabled` was
    /// `!canSave`, so the guard had a button and the test had something to press. The
    /// checkmark is gone, so the fact worth pinning is the one underneath it: the row the
    /// batch was created with is still there, still coloured as it was, and clearing the
    /// colour is staged but not persisted — because `editing` declines to merge a batch with
    /// no colour rather than writing one the user cannot see.
    @Test("Clearing a batch's colour writes nothing and leaves the committed row coloured")
    func clearingColourWritesNothing() async {
        let (_, store, persistence) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        // Settle the writes from creating the batch before counting, or the count races the
        // chain rather than measuring the edit.
        _ = await persistence.waitForWrites(2)
        let writesBefore = await persistence.writes.count

        store.send(.setBatchColor(nil))

        #expect(store.state.assembly?.canSave == false, "precondition: the batch is unwritable")
        #expect(
            await persistence.writes.count == writesBefore,
            "an uncoloured batch resolves to no row, so there is nothing to write"
        )
        #expect(
            store.state.batches.first?.colorName == PCColorOption.firstAvailable.colorName,
            "and the row on the calendar keeps the colour it was written with"
        )
    }

    /// Back is the editor's only exit now, and the batch is already in the registry when it
    /// arrives — which is the whole reason the checkmark was redundant.
    @Test("Backing out of the editor leaves the batch committed and writes nothing new")
    func backCommitsAndCloses() async {
        let (_, store, persistence) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.setBatchName("Morning"))
        store.send(.setBatchColor(.option1))
        #expect(store.state.batches.count == 1, "written on creation, not on the way out")
        // Settle creation and colouring before counting, so the count below measures the write
        // Back causes rather than one still in flight.
        _ = await persistence.waitForWrites(2)
        let writesBefore = await persistence.writes.count

        store.send(.backTapped)

        #expect(store.state.batches.count == 1)
        #expect(store.state.batches.first?.name == "Morning")
        #expect(store.state.assembly == nil, "the assembly has left the line")
        #expect(store.state.navigationRequest?.target == .pop)
        #expect(
            await persistence.writes.count == writesBefore,
            "the row was already in `batches` — `editing` merged it when it was typed, so leaving has nothing to write"
        )
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
