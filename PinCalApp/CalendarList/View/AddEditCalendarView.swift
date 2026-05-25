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
                Button("Закрыть") {
                    dismiss()
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Text("Edit calendar")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding([.top, .bottom])
                
                Spacer()
                
                Button("Сохранить") {
                    Task {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
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
                        
                        TextField("Введите имя", text: $viewModel.label)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal, 4)
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
