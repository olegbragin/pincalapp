//
//  AddEditEventView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 13.03.2026.
//

import SwiftUI

struct AddEditEventView: View {
    @Bindable var viewModel: AddEditEventViewModel
    var onCommit: ((EventDataSource) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
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
                            if let onCommit {
                                onCommit(event)
                            } else {
                                dismiss()
                            }
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
