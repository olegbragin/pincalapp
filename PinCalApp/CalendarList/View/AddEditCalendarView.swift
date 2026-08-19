//
//  AddEditCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 18.03.2026.
//

import SwiftUI

struct AddEditCalendarView: View {
    @Bindable var viewModel: AddEditCalendarViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            // Верхняя панель с кнопками
            HStack {
                PCButton {
                    dismiss()
                } label: {
                    Text("Закрыть")
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Text("Edit calendar")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding([.top, .bottom])
                
                Spacer()
                
                PCButton {
                    Task {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Сохранить")
                }
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            // Форма внутри ScrollView для лучшей прокрутки
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Введите название календаря")
                    
                    // Поле ввода имени
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Имя")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        PCTextField(title: "Введите имя", text: $viewModel.label)
                    }
                }
                .padding()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


#Preview {
    AddEditCalendarView(viewModel: .init())
}
