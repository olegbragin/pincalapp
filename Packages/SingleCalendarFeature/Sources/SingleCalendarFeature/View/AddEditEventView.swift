//
//  AddEditEventView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 13.03.2026.
//

import SwiftUI
import DSKit
import CorePersistence

public struct AddEditEventView: View {
    @Bindable public var viewModel: AddEditEventViewModel
    public var onCommit: ((EventDataSource) -> Void)?

    public init(viewModel: AddEditEventViewModel, onCommit: ((EventDataSource) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onCommit = onCommit
    }
    
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PCDatePicker(
                    title: "Выберите время события",
                    selection: $viewModel.selectedDate,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, TimeZone.current)
                
                // Поле ввода имени
                VStack(alignment: .leading, spacing: 8) {
                    Text("Имя")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    PCTextField(title: "Введите имя", text: $viewModel.eventName, identifier: "event-name-field")
                }
                
                // Выбор цвета
                VStack(alignment: .leading, spacing: 8) {
                    Text("Выберите цвет")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    PCColorPickerView(selectedColor: $viewModel.selectedColor)
                }
                Spacer()
            }
            .padding()
        }
        .keyboardAvoidable()
        .scrollDismissesKeyboard(.interactively)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .title) {
                Text(viewModel.selectedDayToShowEvents ?? Date(), style: .date)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if viewModel.save(), let event = viewModel.event {
                            onCommit?(event)
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Save")
            }
        }
    }
}
