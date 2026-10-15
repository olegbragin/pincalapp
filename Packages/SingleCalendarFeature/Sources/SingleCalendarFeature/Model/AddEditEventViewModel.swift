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

    /// An event's name projects as an **empty** field while it still holds the default, so the
    /// default reads as a placeholder rather than as text the user has to select and delete
    /// before typing over it.
    ///
    /// Masked on *read*, never cleared on write. That is the whole trick, and the alternative
    /// is worse: an `onAppear` that sent `setEventName("")` would make the field empty by
    /// writing an empty name, which is indistinguishable from a user deliberately clearing it
    /// and loses the "this event already has a name" fact the draft carries.
    ///
    /// The stored value is untouched, so leaving the editor without typing costs nothing — the
    /// event keeps `defaultEventName`, and reopening shows the same empty field with the same
    /// placeholder. It also means a user who genuinely wants an event called "New event day"
    /// cannot type it, because the moment they do it stops being the default and reappears as
    /// text. That is accepted rather than worked around: the alternative is a second piece of
    /// state recording "has been edited" so the field could tell the two apart, which is the
    /// kind of flag that disagrees with the value it describes the first time either is cleared
    /// directly.
    var nameBinding: Binding<String> {
        Binding(
            get: {
                guard
                    let name = draft?.name,
                    name != PCEventBatchAssembleUnitOfWork.defaultEventName
                else { return "" }
                return name
            },
            set: { store.send(.setEventName($0)) }
        )
    }

    /// The suggestion shown in the empty field. The event's stored default doubles as its
    /// placeholder, so the field and the store can never disagree about what an unnamed event
    /// is called.
    var namePlaceholder: String {
        PCEventBatchAssembleUnitOfWork.defaultEventName
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
