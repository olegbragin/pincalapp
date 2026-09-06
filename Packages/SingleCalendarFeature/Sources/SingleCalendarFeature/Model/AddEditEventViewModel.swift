//
//  AddEditEventViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.03.2026.
//

import Foundation
import CorePersistence
import CoreDomain
import Observation

@MainActor
@Observable
public final class AddEditEventViewModel {
    /// Shared batch-editing manager. Injected so the view model can apply the
    /// edited event itself instead of leaving it to the view.
    private let eventsSelectionManager: PCEventsSelectionManager

    /// The event being edited, the single source of truth. The view binds to the
    /// computed accessors below instead of a parallel set of fields.
    var event: EventDataSource

    var selectedColor: PCColorOption? {
        get { PCColorOption(event.color) }
        set { event.color = newValue?.colorName ?? "" }
    }

    var eventName: String {
        get { event.name }
        set { event.name = newValue }
    }

    var selectedDate: Date {
        get { event.date }
        set { event.date = newValue }
    }

    var eventId: Int64 {
        get { event.id }
        set { event.id = newValue }
    }

    var timestamp: UUID? {
        get { event.timestamp }
        set { event = event.withTimestamp(newValue) }
    }

    init(
        eventsSelectionManager: PCEventsSelectionManager = PCEventsSelectionManager(),
        event: EventDataSource = .default
    ) {
        self.eventsSelectionManager = eventsSelectionManager
        self.event = event
    }

    var canSave: Bool {
        !event.name.isEmpty && selectedColor != nil
    }

    func save() -> Bool {
        guard canSave else { return false }
        eventsSelectionManager.apply(event)
        return true
    }

    func update(from event: EventDataSource) {
        self.event = event
    }

    func reset() {
        event = .default
    }
}
