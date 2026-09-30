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
@MainActor
public struct AddEditEventListViewModel {
    private let store: PCEventSelectionManager

    init(store: PCEventSelectionManager) {
        self.store = store
    }

    var events: [CalendarEvent] {
        store.state.assembly?.batch.events ?? []
    }

    func open(_ event: CalendarEvent) {
        store.send(.openEvent(pendingID: event.pendingID))
    }

    func remove(_ event: CalendarEvent) {
        store.send(.removeEvent(pendingID: event.pendingID))
    }
}
