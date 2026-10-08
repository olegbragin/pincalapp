//
//  AddEditEventBatchView.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 02.07.2026.
//

import SwiftUI
import DSKit

public struct AddEditEventBatchView: View {
    @Environment(PCEventSelectionManager.self) private var store

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventBatchViewModel(store: store)

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(.name)
                    .font(.headline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    PCTextField(title: String(localized: .enterName), text: viewModel.nameBinding, identifier: "batch-name-field")

                    PCColorPickerView(
                        selectedColor: viewModel.colorBinding,
                        selectColorLabel: String(localized: .selectColor),
                        optionNames: pcColorOptionNames(),
                        defaultColor: viewModel.defaultColor
                    )
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(.events)
                    .font(.headline)
                    .fontWeight(.medium)

                AddEditEventListView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .keyboardAvoidable()
        .toolbarTitleDisplayMode(.inline)
        // No Save, and no toolbar of its own.
        //
        // Every field here writes through as it is edited — `setBatchName` is debounced,
        // `setBatchColor` and `toggleDay` are not — so a checkmark could only re-write a row
        // that was already durable or navigate away from one that was. Worse, it was the
        // *only* exit: `saveTapped` is what cleared `state.assembly` and popped, so removing
        // the button without moving that would have left the editor with no way out. Back,
        // which `AddEditEventBatchScreen` already owns and routes through the store, is now
        // the single exit — and it is the better one, because it does not ask about a save
        // that already happened.
        //
        // Back is also where an emptied batch is deleted. `canSave` is not consulted here
        // at all: it was only ever feeding this button's `isEnabled`.
    }
}

#Preview {
    AddEditEventBatchView()
        .environment(PCKeyboardState())
}
