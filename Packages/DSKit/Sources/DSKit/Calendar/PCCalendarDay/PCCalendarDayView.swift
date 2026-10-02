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
        // Days from the neighbouring months are taken out of the accessibility tree.
        //
        // Two reasons, and the second is the one that mattered. A year grid renders the same
        // day number in every month — day 10 exists twelve times — so a screen reader walking
        // the grid hears twelve "10"s with nothing to say which is real, and the UI suite could
        // not ask for "day 10" without also guessing the month from the wall clock. That guess
        // is what broke these tests at 00:0x on 1 October: the helper built
        // `day-10-2026-10-10` from `Calendar.current` and the grid was showing September, so
        // the test failed on a cell that was plainly on screen.
        //
        // It is also simply more truthful. These days are already greyed out by
        // `textColorRole`, so exposing them as ordinary days told VoiceOver users something
        // the screen was not showing them.
        //
        // Still tappable — `accessibilityHidden` removes it from the tree, it does not
        // disable the view, so tapping a neighbouring month's day still navigates there.
        .accessibilityHidden(!model.isInCurrentMonth)
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
