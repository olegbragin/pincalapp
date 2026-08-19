//
//  ExpandedColorPicker.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct ExpandedColorPicker: View {
    @Binding var selectedColor: ColorOption?
    var defaultColor: ColorOption? = nil
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 24) {
            ForEach(ColorOption.allCases, id: \.self) { colorOption in
                Button {
                    selectedColor = colorOption
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(colorOption.color)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke((selectedColor ?? defaultColor)?.color == colorOption.color ?
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
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }
}

#Preview {
    VStack(spacing: 24) {
        ExpandedColorPicker(selectedColor: .constant(.option1))
        ExpandedColorPicker(selectedColor: .constant(nil))
        ExpandedColorPicker(selectedColor: .constant(.option3))
            .disabled(true)
    }
}
