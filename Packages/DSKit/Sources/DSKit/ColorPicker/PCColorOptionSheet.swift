//
//  PCColorOptionSheet.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct PCColorOptionSheet: View {
    @Binding var selectedColor: PCColorOption?
    var defaultColor: PCColorOption?

    /// The sheet's navigation title.
    public let title: String

    /// How each option is called.
    public let optionNames: PCColorOptionNames

    @Environment(\.pcVibe) private var vibe
    @Environment(\.dismiss) private var dismiss

    /// This sheet, so a test can wait for the sheet itself rather than inferring it from a row.
    public static let sheetAccessibilityIdentifier = "color-option-sheet"

    /// One of its rows.
    ///
    /// **Deliberately not `color-option-<name>`**, which is what `PCExpandedColorPicker` puts on
    /// the inline options it draws on the main calendar during a multi-select session. The two
    /// were the same string, and the batch editor is presented as a sheet *over* that calendar —
    /// so both sets were in the accessibility tree at once and a query for "the colour option"
    /// could resolve to a row of the sheet rather than to the control the test meant. The prefix
    /// says which picker a row belongs to, which is the thing a test actually needs to name.
    public static func optionAccessibilityIdentifier(for option: PCColorOption) -> String {
        "color-sheet-option-\(option.colorName)"
    }

    public init(
        selectedColor: Binding<PCColorOption?>,
        title: String,
        optionNames: PCColorOptionNames,
        defaultColor: PCColorOption? = nil
    ) {
        self._selectedColor = selectedColor
        self.title = title
        self.optionNames = optionNames
        self.defaultColor = defaultColor
    }

    public var body: some View {
        NavigationStack {
            List(PCColorOption.allCases, id: \.self) { colorOption in
                Button {
                    selectedColor = colorOption
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(vibe.eventColor(for: colorOption))
                            .frame(width: 28, height: 28)

                        Text(optionNames.name(for: colorOption))
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
                .accessibilityIdentifier(Self.optionAccessibilityIdentifier(for: colorOption))
            }
            .navigationTitle(title)
            .pcNavigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier(Self.sheetAccessibilityIdentifier)
    }
}

#Preview {
    PCColorOptionSheet(
        selectedColor: .constant(.option1),
        title: "Select color",
        optionNames: PCColorOptionNames { String(describing: $0) }
    )
}
