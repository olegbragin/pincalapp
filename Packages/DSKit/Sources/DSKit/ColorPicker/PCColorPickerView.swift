//
//  PCColorPickerView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.02.2026.
//

import SwiftUI

public struct PCColorPickerView: View {
    public enum Style {
        case compact
        case expanded
    }

    @Binding var selectedColor: PCColorOption?
    public var style: Style = .compact
    public var defaultColor: PCColorOption?

    /// The compact picker's accessibility label and the sheet title.
    ///
    /// Ignored by the expanded picker, which draws its options inline and so has no label of its
    /// own — but kept on the wrapper so a caller sets one value and gets the right behaviour from
    /// either style.
    public let selectColorLabel: String

    /// How each option is called, in either style.
    public let optionNames: PCColorOptionNames

    public init(
        selectedColor: Binding<PCColorOption?>,
        selectColorLabel: String,
        optionNames: PCColorOptionNames,
        style: Style = .compact,
        defaultColor: PCColorOption? = nil
    ) {
        self._selectedColor = selectedColor
        self.selectColorLabel = selectColorLabel
        self.optionNames = optionNames
        self.style = style
        self.defaultColor = defaultColor
    }

    public var body: some View {
        switch style {
        case .compact:
            PCCompactColorPicker(
                selectedColor: $selectedColor,
                selectColorLabel: selectColorLabel,
                optionNames: optionNames,
                defaultColor: defaultColor
            )
        case .expanded:
            PCExpandedColorPicker(
                selectedColor: $selectedColor,
                optionNames: optionNames,
                defaultColor: defaultColor
            )
        }
    }
}

#Preview {
    let names = PCColorOptionNames { _ in "Option" }
    VStack(spacing: 24) {
        PCColorPickerView(selectedColor: .constant(.option1), selectColorLabel: "Select color", optionNames: names)
        PCColorPickerView(selectedColor: .constant(.option2), selectColorLabel: "Select color", optionNames: names, style: .expanded)
    }
}
