//
//  AddEditEventBatchListViewModelTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 08.07.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventBatchListViewModel")
struct AddEditEventBatchListViewModelTests {
    /// Two batches on the *same* day.
    ///
    /// It has to be the same day: a batch's day comes from its first event, so batches
    /// anchored on different days belong to different days and the list for any one day
    /// would only ever hold one of them.
    private var dayOne: Date {
        Fixture.day(1)
    }

    private var rows: [CalendarEventBatch] {
        [
            CalendarEventBatch(
                persistedID: 1,
                name: "Evening",
                colorName: "eventColorOption2",
                events: [Fixture.event("Dinner", on: 1, color: "eventColorOption2")]
            ),
            CalendarEventBatch(
                persistedID: 2,
                name: "Morning",
                colorName: "eventColorOption1",
                events: [Fixture.event("Swim", on: 1, color: "eventColorOption1")]
            ),
        ]
    }

    /// A store opened on `rows`, scrolled to the day that holds them.
    private func makeContext(day: Date? = nil) -> (
        viewModel: AddEditEventBatchListViewModel,
        store: PCEventSelectionManager
    ) {
        let store = Fixture.makeStore(batches: rows, persistence: InMemoryCalendarPersisting())
        // Tapping a day that already has batches opens the day list, which is what sets
        // `state.day` — the list scopes itself to it.
        store.send(.dayTappedInCalendar(day ?? dayOne))
        return (AddEditEventBatchListViewModel(store: store), store)
    }

    @Test("eventBatches is the store's batches for the day, in date order")
    func projectsTheDaysBatches() {
        let (vm, _) = makeContext()

        #expect(vm.selectedDay == dayOne)
        #expect(vm.eventBatches.count == 2)
        // Both are on one day, so the order is the store's own — stable, not arbitrary.
        #expect(Set(vm.eventBatches.map(\.name)) == ["Evening", "Morning"])
    }

    /// Tapping an empty day no longer leaves it empty.
    ///
    /// This asserted the old contract: a tap staged a batch that nothing had written yet, so
    /// the day's list was empty and the batch appeared only after Save. A tap now writes the
    /// batch, which means the day genuinely has one — the assertion that mattered (the list
    /// is derived from `batches`, not cached) is checked below instead.
    @Test("Tapping an empty day writes a batch, and the list projects it")
    func tappingAnEmptyDayWritesABatch() {
        let (vm, store) = makeContext(day: Fixture.day(20))

        // The store still holds the two seeded batches on day 1; the point is that day 20
        // gained one, so the assertion is scoped to the day rather than the whole registry.
        #expect(vm.eventBatches.count == 1, "the tapped day gained exactly one batch")
        #expect(vm.eventBatches.first?.name == "New event", "named by default")
        #expect(store.state.batches.count == 3, "written into the store, not just staged")
    }

    /// The regression §12.5 asks for. The old implementation stored a copy of the list and
    /// had to re-prime it by hand after a delete, because a computed version was found not
    /// to re-render. Deleting *through the store*, with no re-priming and no local
    /// mutation, has to drop the row — which is only true because nothing is stored.
    @Test("Deleting through the store drops the batch, with no re-priming")
    func computedListReflectsADeletion() {
        let (vm, _) = makeContext()
        #expect(vm.eventBatches.count == 2)
        let target = vm.eventBatches[0]

        vm.remove(target)
        #expect(vm.eventBatches.count == 2, "staged, not deleted: the user can still change their mind")
        #expect(vm.pendingDeletion == [target])

        vm.confirmDelete()

        #expect(vm.eventBatches.count == 1, "the projection followed the store")
        #expect(!vm.eventBatches.contains(target))
        #expect(vm.pendingDeletion.isEmpty)
    }

    @Test("Cancelling a staged deletion keeps the batch")
    func cancelKeepsTheBatch() {
        let (vm, _) = makeContext()
        let target = vm.eventBatches[0]

        vm.remove(target)
        vm.cancel()

        #expect(vm.eventBatches.count == 2)
        #expect(vm.eventBatches.contains(target), "there was never a local copy to restore")
        #expect(vm.pendingDeletion.isEmpty)
    }

    @Test("Confirming with nothing staged does nothing")
    func confirmWithNothingStaged() {
        let (vm, _) = makeContext()
        let before = vm.eventBatches

        vm.confirmDelete()

        #expect(vm.eventBatches == before)
    }

    @Test("Opening a batch dispatches openBatch with its durable key")
    func openDispatches() throws {
        let (vm, store) = makeContext()
        let target = try #require(vm.eventBatches.first)

        vm.open(target)

        #expect(store.state.stage == .batchEditor)
        #expect(store.state.assembly?.origin == .existing(pendingID: target.pendingID))
    }

    /// The view model has to send the *durable* key, not `pendingID`.
    ///
    /// The card's closure captures the row as it was when the list last drew. Any write in
    /// between re-syncs the registry and re-mints every `pendingID`, so sending the
    /// captured `pendingID` named a row that no longer existed and the tap was dropped.
    @Test("Opening a batch that a reload has re-minted still opens the same row")
    func openSurvivesRelaoad() throws {
        let (vm, store) = makeContext()
        let target = try #require(vm.eventBatches.first)

        // A reload: same persisted id, nothing else the card relied on.
        let reloaded = CalendarEventBatch(
            persistedID: target.persistedID,
            name: target.name,
            colorName: target.colorName,
            events: target.events
        )
        store.send(.syncCalendar(calendarID: store.state.calendarID, batches: [reloaded]))
        #expect(store.state.batches.first?.pendingID != target.pendingID, "identity re-minted")

        // The user taps the card it was drawn from, still holding the old value.
        vm.open(target)

        #expect(store.state.stage == .batchEditor)
        #expect(
            store.state.assembly?.batch.persistedID == target.persistedID,
            "the persisted id is what the card named, and it survived the reload"
        )
    }

    @Test("Starting a batch dispatches startNewBatch on the given day")
    func startNewBatchDispatches() {
        let (vm, store) = makeContext()

        vm.startNewBatch(on: Fixture.day(9))

        #expect(store.state.stage == .batchEditor)
        #expect(
            store.state.assembly?.batch.events.first?.date
                == store.state.dataProvider.startOfDay(for: Fixture.day(9))
        )
    }
}
