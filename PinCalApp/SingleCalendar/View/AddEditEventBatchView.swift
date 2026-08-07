//
//  AddEditEventBatchView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import SwiftUI

struct AddEditEventBatchView: View {
    @Bindable var viewModel: AddEditEventBatchViewModel
    
    var onSave: () -> Void = {}
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Поле ввода имени с выбором цвета
            VStack(alignment: .leading, spacing: 8) {
                Text("Имя")
                    .font(.headline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    TextField("Введите имя", text: $viewModel.eventBatchName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    ColorPickerView(selectedColor: $viewModel.selectedColor)
                }
                .padding(.horizontal, 4)
                .ignoresSafeArea(.keyboard)
            }
            
            // Events
            VStack(alignment: .leading, spacing: 8) {
                Text("События")
                    .font(.headline)
                    .fontWeight(.medium)
                
                AddEditListView(viewModel: viewModel.addEditListViewModel)
            }
            
            
            Spacer()
        }
        .padding()
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: viewModel.selectedColor) {
            if $0 != $1 {
                viewModel.recolorAllEvents()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        if viewModel.save() {
                            onSave()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    AddEditEventBatchView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
