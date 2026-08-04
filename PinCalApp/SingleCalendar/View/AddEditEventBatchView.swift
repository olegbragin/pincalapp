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
            // Поле ввода имени
            VStack(alignment: .leading, spacing: 8) {
                Text("Имя")
                    .font(.headline)
                    .fontWeight(.medium)
                
                TextField("Введите имя", text: $viewModel.eventBatchName)
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
            
            // Events
            VStack(alignment: .leading, spacing: 8) {
                Text("События")
                    .font(.headline)
                    .fontWeight(.medium)
                
                EventListView(viewModel: viewModel.eventListViewModel)
            }
            
            
            Spacer()
        }
        .padding()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    AddEditEventBatchView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
