//
//  AddEditEventView.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 13.03.2026.
//

import SwiftUI
import AppNavigation
import DSKit

/// The single-event editor.
///
/// Takes no parameters. Which event it is editing was decided by `openEvent(pendingID:)`
/// before this screen was pushed, and it reads that from the store. Dropping the route
/// payload is what makes "editing the wrong event" unexpressible: the screen has no way
/// to be handed an event that disagrees with the store.
public struct AddEditEventView: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(RootNavigation.self) private var navigation

    /// The event editor's only exit, and its one addressable element.
    ///
    /// It was the Save checkmark until the checkmarks went, and it carried the same two jobs
    /// in the UI suite: leaving the editor, and standing in for "the editor is open" because
    /// nothing else on this screen had an identifier.
    ///
    /// Deliberately *not* matched by name. The main calendar's multi-select confirm is also
    /// labelled "Save", so a `toolbarAction("Save")` used to reach this button could resolve
    /// to either depending on what was on screen; an identifier cannot be ambiguous.
    public static let backButtonAccessibilityIdentifier = "event-editor-back-button"

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventViewModel(store: store)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PCDatePicker(
                    title: String(localized: .selectEventTime),
                    selection: viewModel.dateBinding,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, TimeZone.current)

                VStack(alignment: .leading, spacing: 8) {
                    Text(.name)
                        .font(.headline)
                        .fontWeight(.medium)

                    PCTextField(title: String(localized: .enterName), text: viewModel.nameBinding, identifier: "event-name-field")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(.selectColor)
                        .font(.headline)
                        .fontWeight(.medium)

                    PCColorPickerView(
                        selectedColor: viewModel.colorBinding,
                        selectColorLabel: String(localized: .selectColor),
                        optionNames: pcColorOptionNames()
                    )
                }
                Spacer()
            }
            .padding()
        }
        .keyboardAvoidable()
        .scrollDismissesKeyboard(.interactively)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back is the only exit, and it is enough. Each field writes through as it is
            // edited, so the draft is a working copy of an edit that is already durable and
            // Back's `eventDraft = nil` discards nothing — which is exactly what
            // `saveEventTapped`'s re-apply of the draft used to be careful about, and no
            // longer has to be.
            ToolbarItem(placement: .pcLeading) {
                Button {
                    store.send(.backTapped)
                } label: {
                    Label(.back, systemImage: "chevron.backward")
                }
                .accessibilityIdentifier(Self.backButtonAccessibilityIdentifier)
            }
            ToolbarItem(placement: .pcTitle) {
                Text(viewModel.displayedDate, style: .date)
            }
        }
        .onChange(of: store.state.navigationRequest) { _, request in
            guard let request else { return }
            PCEventSelectionNavigator.fulfil(
                request,
                calendarID: store.state.calendarID,
                using: navigation,
                in: store
            )
        }
    }
}

#Preview {
    NavigationStack {
        AddEditEventView()
    }
    .environment(RootNavigation())
    .environment(PCKeyboardState())
}
