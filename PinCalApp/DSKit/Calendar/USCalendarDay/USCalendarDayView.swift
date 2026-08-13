//
//  USCalendarDayView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI

struct USCalendarDayView: View {
    @Bindable var model: USCalendarDayModel
    
    var body: some View {
        ZStack {
            USCalendarDayEventView(
                events: model.events.map(Self.eventColor(for:))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 0.5)
            )

            // Текст
            Text(model.text)
                .font(font)
                .foregroundColor(Color(textColor))
                .background(.clear)
                .lineLimit(1)
                .allowsTightening(true)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier(accessibilityID)
    }
    
    private var accessibilityID: String {
        model.accessibilityID
    }
    
    private static let eventColorsByOption: [String: Color] = Dictionary(
        uniqueKeysWithValues: ColorOption.allCases.map { ($0.colorName, $0.color) }
    )
    
    private static func eventColor(for name: String) -> Color {
        eventColorsByOption[name] ?? Color(name)
    }
    
    private var textColor: Color {
        switch (model.isToday, model.isInCurrentMonth) {
        case (true, true), (true, false):
            return Color("colorForeground")
        case (false, true):
            return Color("colorForeground")
        case (false, false):
            return Color("colorForegroundDisabled")
        }
    }
    
    private static let fontBaseSize: CGFloat = 10

    private var font: Font {
        let font = Font.system(size: Self.fontBaseSize)
        if model.isToday {
            return font.bold()
        }
        return font
    }
    
    private var backgroundColor: Color {
        switch (model.isToday, model.isInCurrentMonth) {
        case (true, true), (true, false):
            return Color("colorBackground")
        case (false, true):
            return Color("colorBackground")
        case (false, false):
            return Color("colorBackgroundDisabled")
        }
    }
    
    private var borderColor: Color {
        switch (model.isToday, model.isInCurrentMonth) {
        case (true, true), (true, false):
            return .red
        default:
            return .clear
        }
    }
}

#Preview {
    USCalendarDayView(
        model: .init(
            dto: .init(
                date: Date(),
                number: 2,
                isInCurrentMonth: true,
                isToday: true
            )
        )
    )
}
