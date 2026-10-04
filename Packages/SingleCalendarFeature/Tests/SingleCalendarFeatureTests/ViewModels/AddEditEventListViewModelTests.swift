//
//  AddEditEventListViewModelTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("AddEditEventListViewModel")
struct AddEditEventListViewModelTests {
    private func makeContext() -> (AddEditEventListViewModel, PCEventSelectionManager) {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        return (AddEditEventListViewModel(store: store), store)
    }

    @Test("With no assembly the list is empty")
    func emptyWithoutAssembly() {
        let (vm, _) = makeContext()
        #expect(vm.events.isEmpty)
    }

    /// §12.4: the list is empty, then reports the assembly's events after `toggleDay`. The
    /// point is that reading it requires no priming and no callback — the old version read
    /// a parallel array on the shared manager.
    @Test("The list reports the assembly's events after a day toggle")
    func reportsTheAssembly() {
        let (vm, store) = makeContext()
        #expect(vm.events.isEmpty)

        store.send(.startNewBatch(on: Fixture.day(4)))
        #expect(vm.events.count == 1)

        store.send(.toggleDay(Fixture.day(5)))
        #expect(vm.events.count == 2)

        store.send(.toggleDay(Fixture.day(5)))
        #expect(vm.events.count == 1, "and toggling the same day off removes it")
    }

    @Test("Events are the assembly's own, in date order")
    func eventsAreSorted() {
        let (vm, store) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(5)))
        store.send(.toggleDay(Fixture.day(2)))
        store.send(.toggleDay(Fixture.day(9)))

        let dates = vm.events.map(\.date)
        #expect(dates == dates.sorted(), "\(dates)")
    }

    @Test("remove dispatches removeEvent for that event's pending id")
    func removeDispatches() {
        let (vm, store) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.toggleDay(Fixture.day(5)))
        let target = vm.events[1]

        vm.remove(target)

        #expect(vm.events.count == 1)
        #expect(!vm.events.contains(target))
    }

    @Test("open dispatches openEvent and stages a draft")
    func openDispatches() throws {
        let (vm, store) = makeContext()
        store.send(.startNewBatch(on: Fixture.day(4)))
        let target = vm.events[0]

        vm.open(target)

        #expect(store.state.eventDraft == target)
        #expect(try store.state.stage == .eventEditor(batchPendingID: #require(store.state.assembly?.batch.pendingID), eventPendingID: target.pendingID))
    }
}
