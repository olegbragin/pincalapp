//
//  AddEditEventViewModel.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 15.03.2026.
//

import Foundation
import SwiftUI
import CoreDomain
import DSKit

/// A projection facade over the store for the single-event editor.
///
/// The event being edited is `state.eventDraft`, not a field. This used to be handed an
/// `EventEditorSource` and keep its own mutable copy, so what the editor displayed and
/// what the batch received were two different events.
@MainActor
public struct AddEditEventViewModel {
    private let store: PCEventSelectionManager

    init(store: PCEventSelectionManager) {
        self.store = store
    }

    private var draft: CalendarEvent? {
        store.state.eventDraft
    }

    /// Shown in the toolbar. Falls back to the assembly's anchor day so the title is
    /// never empty mid-transition.
    var displayedDate: Date {
        draft?.date ?? store.state.day ?? store.state.dataProvider.startOfDay(for: Date())
    }

    var nameBinding: Binding<String> {
        Binding(get: { draft?.name ?? "" }, set: { store.send(.setEventName($0)) })
    }

    var dateBinding: Binding<Date> {
        Binding(get: { draft?.date ?? displayedDate }, set: { store.send(.setEventDate($0)) })
    }

    var colorBinding: Binding<PCColorOption?> {
        Binding(
            get: { draft.flatMap { PCColorOption($0.colorName) } },
            set: { store.send(.setEventColor($0)) }
        )
    }
}
