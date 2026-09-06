//
//  AddEditEventView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 13.03.2026.
//

import SwiftUI
import DSKit
import CorePersistence
import AppNavigation

public struct AddEditEventView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddEditEventViewModel

    public init(eventsSelectionManager: PCEventsSelectionManager, source: EventEditorSource) {
        _viewModel = State(initialValue: AddEditEventViewModel(
            eventsSelectionManager: eventsSelectionManager,
            event: EventDataSource(
                id: source.id,
                name: source.name,
                date: source.date,
                color: source.color,
                timestamp: source.timestamp
            )
        ))
    }
    
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
                Text(viewModel.selectedDate, style: .date)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Save")
                .disabled(!viewModel.canSave)
            }
        }
    }
}
