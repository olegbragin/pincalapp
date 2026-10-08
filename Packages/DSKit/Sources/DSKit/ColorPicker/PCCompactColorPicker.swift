//
//  PCCompactColorPicker.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct PCCompactColorPicker: View {
    @Binding var selectedColor: PCColorOption?
    public var defaultColor: PCColorOption?

    /// This button's accessibility label, and the title of the sheet it opens.
    ///
    /// One string for both because they name the same thing — a split would let them drift, and
    /// they differ in every language.
    public let selectColorLabel: String

    public let optionNames: PCColorOptionNames

    @Environment(\.pcVibe) private var vibe
    @Environment(\.isEnabled) private var isEnabled
    @State private var isColorOptionsPresented = false

    public init(
        selectedColor: Binding<PCColorOption?>,
        selectColorLabel: String,
        optionNames: PCColorOptionNames,
        defaultColor: PCColorOption? = nil
    ) {
        self._selectedColor = selectedColor
        self.selectColorLabel = selectColorLabel
        self.optionNames = optionNames
        self.defaultColor = defaultColor
    }

    public var body: some View {
        Button {
            isColorOptionsPresented = true
        } label: {
            Circle()
                .fill((selectedColor ?? defaultColor).map { vibe.eventColor(for: $0) } ?? Color.secondary.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityLabel(selectColorLabel)
        .accessibilityIdentifier("color-picker-compact")
        .accessibilityValue(selectedColor?.colorName ?? defaultColor?.colorName ?? "")
        .sheet(isPresented: $isColorOptionsPresented) {
            PCColorOptionSheet(
                selectedColor: $selectedColor,
                title: selectColorLabel,
                optionNames: optionNames,
                defaultColor: defaultColor
            )
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PCCompactColorPicker(selectedColor: .constant(.option1), selectColorLabel: "Select color", optionNames: previewOptionNames)
        PCCompactColorPicker(selectedColor: .constant(nil), selectColorLabel: "Select color", optionNames: previewOptionNames)
        PCCompactColorPicker(selectedColor: .constant(.option2), selectColorLabel: "Select color", optionNames: previewOptionNames)
            .disabled(true)
    }
}

/// Previews are not localized — a preview that resolved through the catalog would show
/// whichever language the preview host happens to be in.
private let previewOptionNames = PCColorOptionNames { _ in "Option" }
