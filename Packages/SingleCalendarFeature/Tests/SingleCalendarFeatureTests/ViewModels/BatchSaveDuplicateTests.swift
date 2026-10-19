//
//  BatchSaveDuplicateTests.swift
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
/// A batch used to be committed with `persistedID == nil` while the row that came back from
/// the store had a real one, so the next write found nothing to update and appended a second
/// row. The scenario named this file after the route it used to travel — edit an event in the
/// child editor, then leave the batch — because that was the only way to reach the write
/// twice. The editor is gone, so the first test went with it; what is left is the mechanism
/// itself, which never needed it.
///
/// This used to run against a real ObjectBox store through `SingleCalendarModel`. It no
/// longer can: the DTO→domain adapter (`CalendarStore`) is in the app target, not in a
/// package, and that separation is the point of the boundary — a package test cannot name
/// `EventBatchDataSource` and should not. The scenario is preserved against the port, and
/// the ObjectBox round trip is covered where the adapter lives, in `PinCalAppTests`.
@MainActor
@Suite("Leaving a batch does not duplicate it")
struct BatchSaveDuplicateTests {
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
