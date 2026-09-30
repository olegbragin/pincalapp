//
//  AddEditCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 18.03.2026.
//

import SwiftUI
import DSKit

public struct AddEditCalendarView: View {
    @Bindable var viewModel: AddEditCalendarViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        VStack {
            // Верхняя панель с кнопками
            HStack {
                PCButton(action: { dismiss() }, identifier: "add-calendar-close-button") {
                    Text("Закрыть")
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Text("Edit calendar")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding([.top, .bottom])
                
                Spacer()
                
                PCButton(
                    action: {
                        Task {
                            if viewModel.save() {
                                dismiss()
                            }
                        }
                    },
                    identifier: "add-calendar-save-button"
                ) {
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
                            .accessibilityIdentifier("add-calendar-name-field")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Deliberately **no** identifier on this root.
        //
        // It was here while diagnosing "why is `add-calendar-save-button` unfindable", and it
        // was the answer: an identifier on a container's root is pushed down onto its
        // descendants and **overrides theirs**. Every control in the sheet was reporting
        // `add-calendar-sheet` — dumped straight out of the tree as
        // `Сохранить ~ add-calendar-sheet` — so a correctly-placed identifier on the button
        // was being silently replaced by the parent's.
        //
        // This is also the more likely explanation for §18, where putting identifiers on the
        // split view's column roots broke 30 tests: not that an identifier rewrites the tree,
        // but that it shadows everything beneath it. A container identifier is not additive —
        // it is destructive to its children.
    }
}


#Preview {
    AddEditCalendarView(viewModel: .init())
}
