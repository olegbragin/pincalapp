//
//  PCExpandedColorPicker.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct PCExpandedColorPicker: View {
    @Binding var selectedColor: PCColorOption?
    public var defaultColor: PCColorOption? = nil
    @Environment(\.isEnabled) private var isEnabled

    public init(selectedColor: Binding<PCColorOption?>, defaultColor: PCColorOption? = nil) {
        self._selectedColor = selectedColor
        self.defaultColor = defaultColor
    }

    public var body: some View {
        HStack(spacing: 24) {
            ForEach(PCColorOption.allCases, id: \.self) { colorOption in
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
        PCExpandedColorPicker(selectedColor: .constant(.option1))
        PCExpandedColorPicker(selectedColor: .constant(nil))
        PCExpandedColorPicker(selectedColor: .constant(.option3))
            .disabled(true)
    }
}