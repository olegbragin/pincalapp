//
//  AddEditEventBatchView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import SwiftUI

struct AddEditEventBatchView: View {
    @Bindable var viewModel: AddEditEventBatchViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DatePicker(
                selection: $viewModel.selectedDate,
                displayedComponents: .hourAndMinute
            ) {
                Text("Выберите время события")
            }
            .environment(\.timeZone, TimeZone.current)
            
            // Поле ввода имени
            VStack(alignment: .leading, spacing: 8) {
                Text("Имя")
                    .font(.headline)
                    .fontWeight(.medium)
                
                TextField("Введите имя", text: $viewModel.eventName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 4)
                    .ignoresSafeArea(.keyboard)
            }
            
            // Выбор цвета
            VStack(alignment: .leading, spacing: 8) {
                Text("Выберите цвет")
                    .font(.headline)
                    .fontWeight(.medium)
                
                ColorPickerView(selectedColor: $viewModel.selectedColor)
            }
            
            // Selected days / events
            VStack(alignment: .leading, spacing: 8) {
                Text("Выбранные дни")
                    .font(.headline)
                    .fontWeight(.medium)
                
                EventListView(viewModel: EventListViewModel())
            }
            
            
            Spacer()
        }
        .padding()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .title) {
                Text(viewModel.selectedDayToShowEvents ?? Date(), style: .date)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    AddEditEventBatchView(viewModel: .init())
}
