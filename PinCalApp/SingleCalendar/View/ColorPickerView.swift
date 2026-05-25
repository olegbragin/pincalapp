//
//  ColorPickerView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 24.02.2026.
//

import SwiftUI

struct ColorPickerView: View {
    @Binding var selectedColor: ColorOption?
    let colors: [ColorOption] = ColorOption.allCases
    
    var body: some View {
        HStack(spacing: 24) {
            ForEach(colors, id: \.self) { colorOption in
                Button(action: {
                    selectedColor = colorOption
                }) {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(colorOption.color)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor?.color == colorOption.color ?
                                            Color.accentColor : Color.clear,
                                            lineWidth: 3)
                            )
                        
                        Text(colorOption.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    ColorPickerView(selectedColor: .constant(.option1))
}
