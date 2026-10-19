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
        #expect(
            store.state.assembly?.canSave == false,
            "a new batch arrives coloured but unnamed, so it is a draft until it is named"
        )
    }

    /// The field opens empty and offers the old default, rather than arriving pre-filled with it.
    ///
    /// This is the visible half of the draft rule. Pre-filling it would be read by `editing` as
    /// a rename on the first unrelated keystroke and write the batch, which is precisely the
    /// permanent-misclick behaviour the empty stored name exists to prevent.
    @Test("A new batch's name field is empty and offers the default as a placeholder")
    func newBatchProjectsAnEmptyNameWithAPlaceholder() {
        let (vm, store, _) = makeContext()

        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(store.state.assembly?.batch.name.isEmpty == true, "stored empty, so it stays a draft")
        #expect(vm.name.isEmpty, "so the field shows nothing")
        #expect(vm.namePlaceholder == "New event", "and offers the default instead")
    }

    /// A batch needs a **name and** a colour to be written.
    ///
    /// **Premise changed.** This said the opposite in its name and in its body: "Colour is what
    /// `canSave` reads. The name deliberately is not", arguing that a batch is a set of dated,
    /// coloured events and that refusing to write an untitled one would leave the store ahead
    /// of the database with nowhere to put the work.
    ///
    /// The name is now required too, and the order of the two assertions follows the order the
    /// arguments used to be made in — colour first, because it is the one that arrives free.
    ///
    /// Asserted on the assembly rather than on `AddEditEventBatchViewModel.canSave`, which is
    /// gone with the checkmark it fed. A projection nothing renders is a projection that can
    /// drift from the domain without anything noticing — which is how `canSave` came to need a
    /// test of its own in the first place.
    @Test("A batch needs a name and a colour to be written")
    func writableRequirements() {
        let (_, store, _) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))

        #expect(store.state.assembly?.canSave == false, "a new batch arrives unnamed, so it is a draft")
        store.send(.setBatchName("Morning"))
        #expect(store.state.assembly?.canSave == true, "naming it is what makes it writable")
        store.send(.setBatchName(""))
        #expect(store.state.assembly?.canSave == false, "and erasing the name takes it back to a draft")
        store.send(.setBatchName("Morning"))
        store.send(.setBatchColor(nil))
        #expect(store.state.assembly?.canSave == false, "no colour stops a write too")
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
    /// **Premise changed twice.** This used to assert that *Save* on an uncoloured batch wrote
    /// nothing and left the editor open — the checkmark's `isEnabled` was `!canSave`, so the
    /// guard had a button and the test had something to press. The checkmark is gone. Then it
    /// came to rely on the creation step having written the row ("the row the batch was created
    /// with"), which is also gone: a new batch is a draft until it is edited. The row is now
    /// written by a colour change, which is a discrete write rather than a debounced name, and
    /// the claim underneath is unchanged — an uncoloured batch has no row to write, and
    /// clearing the colour leaves the committed row as it was.
    @Test("Clearing a batch's colour writes nothing and leaves the committed row coloured")
    func clearingColourWritesNothing() async {
        let (_, store, persistence) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        // Both halves are needed before a draft is written, and the *name* is what makes it
        // real — this used to reach the same state with a colour alone, which stopped being
        // true once an unnamed batch stopped being written.
        store.send(.setBatchName("Morning"))
        store.send(.setBatchColor(.option2))
        #expect(store.state.batches.count == 1, "setup: the batch is committed")
        // Settle the write from colouring the batch before counting, or the count races the
        // chain rather than measuring the edit.
        _ = await persistence.waitForWrites(1)
        let writesBefore = await persistence.writes.count

        store.send(.setBatchColor(nil))

        #expect(store.state.assembly?.canSave == false, "precondition: the batch is unwritable")
        #expect(
            await persistence.writes.count == writesBefore,
            "an uncoloured batch resolves to no row, so there is nothing to write"
        )
        #expect(
            store.state.batches.first?.colorName == PCColorOption.option2.colorName,
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
        // `.dismissBatchEditor` rather than `.pop`: the editor is a sheet, so its Back has to
        // dismiss that sheet. `.pop` removes the top of the calendar's stack, and there is no
        // editor on it — Back would have been a button that visibly did nothing.
        #expect(store.state.navigationRequest?.target == .dismissBatchEditor)
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
