//
//  EventEditorThenBatchSaveDuplicateTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// The reported duplicate-batch bug, end to end through the store.
///
/// Edit an event from the child event editor, then leave the batch. The batch used to be
/// committed with `persistedID == nil` while the row that came back from the store had a
/// real one, so the next write found nothing to update and appended a second row.
///
/// This used to run against a real ObjectBox store through `SingleCalendarModel`. It no
/// longer can: the DTO→domain adapter (`CalendarStore`) is in the app target, not in a
/// package, and that separation is the point of the boundary — a package test cannot name
/// `EventBatchDataSource` and should not. The scenario is preserved against the port, and
/// the ObjectBox round trip is covered where the adapter lives, in `PinCalAppTests`.
@MainActor
@Suite("Editing an event then leaving its batch does not duplicate the batch")
struct EventEditorThenBatchSaveDuplicateTests {
    @Test func editingEventThenLeavingBatchDoesNotDuplicateNewBatch() {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(persistence: persistence)
        let batchViewModel = AddEditEventBatchViewModel(store: store)

        let day = Fixture.day(3)

        // Tap the day: an empty day stages a new batch and opens the editor.
        store.send(.startNewBatch(on: day))
        #expect(store.state.assembly?.isNew == true)

        // Name it, so it is written.
        batchViewModel.nameBinding.wrappedValue = "Swim"
        batchViewModel.colorBinding.wrappedValue = .option1
        #expect(store.state.assembly?.canSave == true)

        // Open the child event editor, rename the event, and leave it.
        let listViewModel = AddEditEventListViewModel(store: store)
        let event = listViewModel.events[0]
        listViewModel.open(event)
        let eventViewModel = AddEditEventViewModel(store: store)
        eventViewModel.nameBinding.wrappedValue = "Lap"

        #expect(
            store.state.assembly?.batch.events.first?.name == "Lap",
            "already in the batch while the event editor is still open"
        )
        store.send(.backTapped)

        #expect(store.state.eventDraft == nil, "the draft is dropped on the way out")
        #expect(store.state.assembly?.batch.events.count == 1, "edited, not appended")

        // Leave the batch editor.
        store.send(.backTapped)

        #expect(store.state.batches.count == 1, "one row, not two")
        #expect(store.state.batches.first?.name == "Swim")
    }

    /// The second half of the original bug: the committed row comes back from the store
    /// under a real id, and the *next* write must update it rather than append. That is
    /// §6.5 adoption, and the store's write is what makes the id real.
    @Test func reopeningAndEditingUpdatesTheSameRow() async {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(persistence: persistence)
        let batchViewModel = AddEditEventBatchViewModel(store: store)

        store.send(.startNewBatch(on: Fixture.day(3)))
        batchViewModel.nameBinding.wrappedValue = "Swim"
        batchViewModel.colorBinding.wrappedValue = .option1
        store.send(.backTapped)
        #expect(store.state.batches.count == 1)

        // Wait for the write chain, then read the row back as the store would.
        _ = await persistence.waitForWrites(1)
        var stored = await persistence.storedBatches(calendarID: 42)
        #expect(stored.count == 1)
        #expect(stored[0].persistedID != nil, "the store assigns ids on write")

        // Reopen the row and rename it. The reload mints a fresh pendingID, which is why
        // adoption has to be content-based rather than an id lookup.
        stored[0] = CalendarEventBatch(
            pendingID: UUID(),
            persistedID: stored[0].persistedID,
            name: stored[0].name,
            colorName: stored[0].colorName,
            events: stored[0].events.map {
                CalendarEvent(
                    name: $0.name,
                    date: $0.date,
                    colorName: $0.colorName
                )
            }
        )
        store.send(.syncCalendar(calendarID: 42, batches: stored))
        #expect(store.state.batches.count == 1)

        store.send(.openBatch(id: stored[0].mergeKey))
        batchViewModel.nameBinding.wrappedValue = "Swimming"
        store.send(.backTapped)

        #expect(store.state.batches.count == 1, "still one row")
        #expect(store.state.batches.first?.name == "Swimming")
        #expect(store.state.batches.first?.persistedID == stored[0].persistedID, "and it is the same row")
    }
}
