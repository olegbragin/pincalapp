//
//  AddEditEventListViewModel.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import CoreDomain
import DSKit

/// A projection facade over the store for the list of events inside a batch.
///
/// The list *is* the assembly's events, not a list this object owns. The old version read
/// a parallel `events` array on the shared manager, so toggling a day in the editor
/// calendar and reading the list were two different views of one thing and could disagree.
///
/// There is no selection *mode* here any more. The list is always in edit, so a row's
/// checkbox is a control like any other and the projection has nothing to say about whether
/// one happens to be in focus — which is why `isSelecting`, `setSelecting`, `selectAll`,
/// `clearSelection` and `selectedCount` are gone rather than merely unread. The reducer's
/// `.setEventSelectionMode` and friends still exist and are still tested; nothing dispatches
/// them from here.
@MainActor
public struct AddEditEventListViewModel {
    private let store: PCEventSelectionManager

    init(store: PCEventSelectionManager) {
        self.store = store
    }

    var events: [CalendarEvent] {
        store.state.assembly?.batch.events ?? []
    }

    /// The row's second line: the event's date *and* time, e.g. "Jul 15, 2026 at 3:45 PM".
    ///
    /// The format itself belongs to `CalendarEvent.dateTimeText`, which the batch card's
    /// view model also reads — two screens list the same event, and two copies of the format
    /// is how they start disagreeing about it. Projecting it here keeps the view free of it.
    func dateTimeText(for event: CalendarEvent) -> String {
        event.dateTimeText
    }

    // MARK: - Selection

    var selectedIDs: Set<UUID> {
        store.state.selectedEventIDs
    }

    func isSelected(_ event: CalendarEvent) -> Bool {
        selectedIDs.contains(event.pendingID)
    }

    func toggleSelection(_ event: CalendarEvent) {
        store.send(.toggleEventSelection(pendingID: event.pendingID))
    }

    // MARK: - Commands

    func open(_ event: CalendarEvent) {
        store.send(.openEvent(pendingID: event.pendingID))
    }

    func remove(_ event: CalendarEvent) {
        store.send(.removeEvent(pendingID: event.pendingID))
    }
}
