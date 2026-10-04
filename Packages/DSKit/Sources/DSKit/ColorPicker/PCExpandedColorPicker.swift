//
//  PCExpandedColorPicker.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct PCExpandedColorPicker: View {
    @Binding var selectedColor: PCColorOption?
    public var defaultColor: PCColorOption?
    @Environment(\.pcVibe) private var vibe
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
                            .fill(vibe.eventColor(for: colorOption))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(
                                        (selectedColor ?? defaultColor) == colorOption ?
                                            Color.accentColor : Color.clear,
                                        lineWidth: 3
                                    )
                            )

                        Text(colorOption.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                // Same contract as the sheet the compact picker opens, so a UI test can
                // pick a colour without depending on `name` — which is a localised label,
                // and the stage 11 multi-day test needs to be able to name a colour here.
                .accessibilityIdentifier("color-option-\(colorOption.colorName)")
            }
        }
        .padding(.horizontal)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        // Its own accessibility container. Without this the whole subtree is flattened into
        // whatever identifier an ancestor put on it — `CalendarDetailView` stamps
        // `calendar-detail-<id>` on the screen — and every option button reports that
        // instead of its own, which is what the stage 11 test found. The options keep their
        // human labels either way; this only stops the parent identifier overwriting the
        // per-option ones.
        .accessibilityElement(children: .contain)
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
