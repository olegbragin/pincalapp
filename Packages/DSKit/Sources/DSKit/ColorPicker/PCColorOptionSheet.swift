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
                .accessibilityIdentifier("color-option-\(colorOption.colorName)")
            }
            .navigationTitle(title)
            .pcNavigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PCColorOptionSheet(
        selectedColor: .constant(.option1),
        title: "Select color",
        optionNames: PCColorOptionNames { String(describing: $0) }
    )
}
