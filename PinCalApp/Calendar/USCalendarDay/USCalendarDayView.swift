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
                events: model.events.map {
                    Color($0)
                }
            )
            .drawingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .aspectRatio(1, contentMode: .fit)
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
        }
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
    
    private var font: Font {
        var font = Font.caption
        if model.isToday {
            font = font.bold()
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
