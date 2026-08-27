//
//  PCColorOptionSheet.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct PCColorOptionSheet: View {
    @Binding var selectedColor: PCColorOption?
    var defaultColor: PCColorOption? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(PCColorOption.allCases, id: \.self) { colorOption in
                Button {
                    selectedColor = colorOption
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(colorOption.color)
                            .frame(width: 28, height: 28)
                        
                        Text(colorOption.name)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if selectedColor == colorOption {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        } else if selectedColor == nil, defaultColor == colorOption {
                            Image(systemName: "checkmark")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("color-option-\(colorOption.colorName)")
            }
            .navigationTitle("Выберите цвет")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PCColorOptionSheet(selectedColor: .constant(.option1))
}
