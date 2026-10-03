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

    @Test("With no draft, the name is empty")
    func noDraft() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        let vm = AddEditEventViewModel(store: store)

        #expect(store.state.eventDraft == nil, "precondition: nothing is being edited")
        #expect(vm.nameBinding.wrappedValue.isEmpty)
    }

    /// §12.4: projections track `state.eventDraft`. The old version kept its own mutable
    /// `event`, so these assertions are about the *store* moving rather than a local field.
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

    /// The time of day has to survive the trip into the batch, not just the draft.
    ///
    /// The picker's binding and the draft both carried it, and `PCEventBatchAssembleUnitOfWork.applying`
    /// threw it away on the way in — normalising the event's date to the start of its day.
    /// So the batch went on listing the event at 12:00 AM and reopening the event showed the
    /// picker back at midnight, while everything in the editor looked correct. Asserting on the
    /// draft alone is exactly what let that through: it is the one place the time still was.
    @Test("A time picked in the editor reaches the batch, time component and all")
    func pickedTimeReachesTheBatch() throws {
        let (vm, store) = makeContext()
        // 19:00 *local*, on the day the placeholder occupies. `Fixture.day` is noon UTC, so
        // adding 19 hours to it lands on 07:00 somewhere else entirely — the point is a
        // non-midnight hour component, and it has to be built in the zone it is read back in.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let sevenPm = try #require(
            local.date(bySettingHour: 19, minute: 0, second: 0, of: Fixture.day(4))
        )

        vm.dateBinding.wrappedValue = sevenPm

        let inBatch = try #require(store.state.assembly?.batch.events.first?.date)
        #expect(inBatch == sevenPm, "the batch holds 19:00, not \(inBatch)")
        #expect(
            local.component(.hour, from: inBatch) == 19,
            "and the hour component really is 19 — not a midnight that happens to compare equal"
        )
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

    /// What replaced `saveCommits`: there is no Save, so the batch has to be current before
    /// the user leaves. This is the invariant that made the checkmark redundant, so it is the
    /// one worth pinning — the old test asserted the draft was committed *by pressing Save*,
    /// which passed while the writes were already happening on every keystroke.
    @Test("The draft is written into the batch as it is typed, with no Save")
    func editsReachTheBatchWithoutSaving() {
        let (vm, store) = makeContext()
        // The push from `openEvent` is still pending — the view layer has not reported back —
        // so "no new navigation" means this request, unchanged.
        let pendingOnEntry = store.state.navigationRequest
        vm.nameBinding.wrappedValue = "Swim"
        vm.colorBinding.wrappedValue = .option2

        #expect(
            store.state.assembly?.batch.events.first?.name == "Swim",
            "already in the batch, while the editor is still open"
        )
        #expect(store.state.assembly?.batch.events.first?.colorName == "eventColorOption2")
        #expect(store.state.stage == .eventEditor(batchPendingID: store.state.assembly!.batch.pendingID, eventPendingID: store.state.eventDraft!.pendingID))
        #expect(
            store.state.navigationRequest == pendingOnEntry,
            "and nothing new navigated: there is nothing to commit"
        )
    }

    /// Leaving is Back, and it drops the draft without losing the edit — the draft is a
    /// working copy of an already-durable change, not a pending one.
    ///
    /// This is the test that says the removed checkmark was redundant. `saveEventTapped` used
    /// to re-apply the draft on the way out "so nothing is lost", which was only ever true
    /// because nothing had been lost in the first place.
    @Test("Backing out keeps the edit and clears the draft")
    func backKeepsTheEditAndDropsTheDraft() {
        let (vm, store) = makeContext()
        vm.nameBinding.wrappedValue = "Swim"

        store.send(.backTapped)

        #expect(store.state.eventDraft == nil, "the working copy is gone")
        #expect(store.state.stage == .batchEditor)
        #expect(
            store.state.assembly?.batch.events.first?.name == "Swim",
            "and the edit is still in the batch"
        )
        #expect(store.state.navigationRequest?.target == .pop)
    }
}
