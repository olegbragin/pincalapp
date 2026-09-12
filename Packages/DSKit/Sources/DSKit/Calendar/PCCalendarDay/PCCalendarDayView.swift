//
//  PCCalendarDayView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI

public struct PCCalendarDayView: View {
    @Environment(\.pcVibe) private var vibe
    @Bindable var model: PCCalendarDayModel
    
    var cellSize: CGFloat
    
    public var body: some View {
        ZStack {
            PCCalendarDayEventView(
                events: model.events.map { vibe.eventColor(named: $0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(vibe.color(for: model.backgroundColorRole))
            )
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        model.borderColorRole.map { vibe.color(for: $0) } ?? .clear,
                        lineWidth: 0.5
                    )
            )

            // Текст
            Text(model.text)
                .font(vibe.font(for: model.fontRole, cellSize: cellSize))
                .foregroundColor(Color(vibe.color(for: model.textColorRole)))
                .background(.clear)
                .lineLimit(1)
                .allowsTightening(true)
                .padding(.horizontal, 2)
        }
        .frame(width: cellSize, height: cellSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityIdentifier(model.accessibilityID)
    }
}

#Preview {
    PCCalendarDayView(
        model: .init(
            date: Date(),
            number: 2,
            isInCurrentMonth: true,
            isToday: true,
            gridMonth: 2
        ),
        cellSize: 50
    )
}
