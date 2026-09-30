//
//  AddEditEventView.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 13.03.2026.
//

import SwiftUI
import DSKit
import AppNavigation

/// The single-event editor.
///
/// Takes no parameters. Which event it is editing was decided by `openEvent(pendingID:)`
/// before this screen was pushed, and it reads that from the store. Dropping the route
/// payload is what makes "editing the wrong event" unexpressible: the screen has no way
/// to be handed an event that disagrees with the store.
public struct AddEditEventView: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(RootNavigation.self) private var navigation

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventViewModel(store: store)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PCDatePicker(
                    title: "Выберите время события",
                    selection: viewModel.dateBinding,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, TimeZone.current)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Имя")
                        .font(.headline)
                        .fontWeight(.medium)

                    PCTextField(title: "Введите имя", text: viewModel.nameBinding, identifier: "event-name-field")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Выберите цвет")
                        .font(.headline)
                        .fontWeight(.medium)

                    PCColorPickerView(selectedColor: viewModel.colorBinding)
                }
                Spacer()
            }
            .padding()
        }
        .keyboardAvoidable()
        .scrollDismissesKeyboard(.interactively)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .pcTitle) {
                Text(viewModel.displayedDate, style: .date)
            }
            ToolbarItem(placement: .pcTrailing) {
                Button {
                    viewModel.save()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Save")
                .disabled(!viewModel.canSave)
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
