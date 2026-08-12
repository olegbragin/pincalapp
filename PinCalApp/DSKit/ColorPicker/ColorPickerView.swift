//
//  ColorPickerView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.02.2026.
//

import SwiftUI

struct ColorPickerView: View {
    enum Style {
        case compact
        case expanded
    }
    
    @Binding var selectedColor: ColorOption?
    var style: Style = .compact
    var defaultColor: ColorOption? = nil
    @State private var isColorOptionsPresented = false
    
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        switch style {
        case .compact:
            compactPicker
        case .expanded:
            expandedPicker
        }
    }
    
    private var compactPicker: some View {
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
        .sheet(isPresented: $isColorOptionsPresented) {
            ColorOptionSheet(selectedColor: $selectedColor, defaultColor: defaultColor)
        }
    }
    
    private var expandedPicker: some View {
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

private struct ColorOptionSheet: View {
    @Binding var selectedColor: ColorOption?
    var defaultColor: ColorOption? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(ColorOption.allCases, id: \.self) { colorOption in
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
            }
            .navigationTitle("Выберите цвет")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    VStack(spacing: 24) {
        ColorPickerView(selectedColor: .constant(.option1))
        ColorPickerView(selectedColor: .constant(.option2), style: .expanded)
    }
}
