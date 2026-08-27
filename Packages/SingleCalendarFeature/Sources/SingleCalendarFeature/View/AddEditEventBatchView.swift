//
//  AddEditEventBatchView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import SwiftUI
import DSKit

public struct AddEditEventBatchView: View {
    @Bindable public var viewModel: AddEditEventBatchViewModel
    
    public var onSave: () -> Void = {}
    
    public init(viewModel: AddEditEventBatchViewModel, onSave: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onSave = onSave
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Поле ввода имени с выбором цвета
            VStack(alignment: .leading, spacing: 8) {
                Text("Имя")
                    .font(.headline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    PCTextField(title: "Введите имя", text: $viewModel.eventBatchName, identifier: "batch-name-field")
                    
                    PCColorPickerView(selectedColor: $viewModel.selectedColor, defaultColor: viewModel.defaultColor)
                }
                .padding(.horizontal, 4)
            }
            
            // Events
            VStack(alignment: .leading, spacing: 8) {
                Text("События")
                    .font(.headline)
                    .fontWeight(.medium)
                
                AddEditListView(viewModel: viewModel.addEditListViewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .keyboardAvoidable()
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: viewModel.selectedColor) {
            if $0 != $1 {
                viewModel.recolorAllEvents()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PCButton {
                    Task {
                        if viewModel.save() {
                            onSave()
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Save")
                }
                .disabled(!viewModel.canSave)
            }
        }
    }
}

#Preview {
    AddEditEventBatchView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
        .environment(PCKeyboardState())
}
