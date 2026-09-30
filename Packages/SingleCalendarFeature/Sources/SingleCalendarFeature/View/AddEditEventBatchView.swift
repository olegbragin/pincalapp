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

    public static let saveButtonAccessibilityIdentifier = "batch-save-button"

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventBatchViewModel(store: store)

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Имя")
                    .font(.headline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    PCTextField(title: "Введите имя", text: viewModel.nameBinding, identifier: "batch-name-field")

                    PCColorPickerView(selectedColor: viewModel.colorBinding, defaultColor: viewModel.defaultColor)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("События")
                    .font(.headline)
                    .fontWeight(.medium)

                AddEditEventListView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .keyboardAvoidable()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .pcTrailing) {
                PCButton {
                    viewModel.save()
                } label: {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Save")
                }
                .accessibilityIdentifier(Self.saveButtonAccessibilityIdentifier)
                .disabled(!viewModel.canSave)
            }
        }
    }
}

#Preview {
    AddEditEventBatchView()
        .environment(PCKeyboardState())
}
