//
//  PCCompactColorPicker.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct PCCompactColorPicker: View {
    @Binding var selectedColor: PCColorOption?
    var defaultColor: PCColorOption? = nil
    @Environment(\.isEnabled) private var isEnabled
    @State private var isColorOptionsPresented = false

    var body: some View {
        Button {
            isColorOptionsPresented = true
        } label: {
            Circle()
                .fill((selectedColor ?? defaultColor)?.color ?? Color.secondary.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityLabel("Выберите цвет")
        .accessibilityIdentifier("color-picker-compact")
        .accessibilityValue(selectedColor?.colorName ?? defaultColor?.colorName ?? "")
        .sheet(isPresented: $isColorOptionsPresented) {
            PCColorOptionSheet(selectedColor: $selectedColor, defaultColor: defaultColor)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PCCompactColorPicker(selectedColor: .constant(.option1))
        PCCompactColorPicker(selectedColor: .constant(nil))
        PCCompactColorPicker(selectedColor: .constant(.option2))
            .disabled(true)
    }
}
