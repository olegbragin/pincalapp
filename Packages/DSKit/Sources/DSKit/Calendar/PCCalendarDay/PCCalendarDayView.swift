//
//  PCCalendarDayView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI

public struct PCCalendarDayView: View {
    @Bindable var model: PCCalendarDayModel
    var cellSize: CGFloat
    
    public var body: some View {
        ZStack {
            PCCalendarDayEventView(
                events: eventColors
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 0.5)
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
        .frame(width: cellSize, height: cellSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityID)
    }
    
    private var accessibilityID: String {
        model.accessibilityID
    }
    
    private var accessibilityLabel: String {
        if model.events.isEmpty {
            return model.text
        }
        return "\(model.text), \(model.events.count) events"
    }
    
    private static let eventColorsByOption: [String: Color] = Dictionary(
        uniqueKeysWithValues: PCColorOption.allCases.map { ($0.colorName, $0.color) }
    )
    
    private static func eventColor(for name: String) -> Color {
        eventColorsByOption[name] ?? Color(name)
    }
    
    private static var eventColorsCache: [[String]: [Color]] = [:]
    
    private var eventColors: [Color] {
        if let cached = Self.eventColorsCache[model.events] {
            return cached
        }
        let colors = model.events.map(Self.eventColor(for:))
        Self.eventColorsCache[model.events] = colors
        return colors
    }
    
    private var textColor: Color {
        switch (model.isToday, model.isInCurrentMonth) {
        case (true, true), (true, false):
            return Color("colorForeground", bundle: .module)
        case (false, true):
            return model.events.isEmpty ? Color("colorForeground", bundle: .module) : Color("colorForegroundEvent", bundle: .module)
        case (false, false):
            return Color("colorForegroundDisabled", bundle: .module)
        }
    }
    
    private static let fontMinSize: CGFloat = 10
    private static let fontMaxSize: CGFloat = 20
    private static let fontSizeToCellRatio: CGFloat = 0.49
    private static let fontDigitsWidthRatio: CGFloat = 1.3
    private static let cellPadding: CGFloat = 2

    private var fontSize: CGFloat {
        let fitSize = (cellSize - Self.cellPadding * 2) / Self.fontDigitsWidthRatio
        return min(
            max(cellSize * Self.fontSizeToCellRatio, Self.fontMinSize),
            min(Self.fontMaxSize, fitSize)
        )
    }

    private var font: Font {
        let font = Font.system(size: fontSize)
        if model.isToday {
            return font.bold()
        }
        return font
    }
    
    private var backgroundColor: Color {
        switch (model.isToday, model.isInCurrentMonth) {
        case (true, true), (true, false):
            return Color("colorBackground", bundle: .module)
        case (false, true):
            return Color("colorBackground", bundle: .module)
        case (false, false):
            return Color("colorBackgroundDisabled", bundle: .module)
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
    PCCalendarDayView(
        model: .init(
            dto: .init(
                date: Date(),
                number: 2,
                isInCurrentMonth: true,
                isToday: true
            )
        ),
        cellSize: 50
    )
}