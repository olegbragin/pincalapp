//
//  SwiftUIView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI
import CoreDomain

public struct PCCalendarWeekView: View {
    // Для тактильной отдачи
    private static let hapticFeedback = UINotificationFeedbackGenerator()
    
    @Bindable var viewModel: PCCalendarWeekModel
    var cellSize: CGFloat
    
    public var body: some View {
        GridRow {
            ForEach(viewModel.days, id: \.id) { day in
                PCCalendarDayView(
                    model: day,
                    cellSize: cellSize
                )
                .padding(.bottom, 0)
                .onTapGesture {
                    viewModel.select(day: day)
                }
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { _ in
                            viewModel.daySelectionManager.selectionMode = .multiple
                            Self.hapticFeedback.notificationOccurred(.success)
                        },
                    isEnabled: viewModel.daySelectionManager.selectionMode == .single
                )
            }
        }
        .onChange(of: viewModel.daySelectionManager.selectionMode) { oldValue, newValue in
            if oldValue != newValue, newValue == .multiple {
                Self.hapticFeedback.notificationOccurred(.success)
            }
        }
    }
}

#Preview {
    Grid {
        PCCalendarWeekView(
            viewModel: .init(
                dto: .init(
                    number: 4,
                    days: [
                        .init(date: Date(), number: 44, isInCurrentMonth: true, isToday: false),
                        .init(date: Date(), number: 43, isInCurrentMonth: true, isToday: false),
                        .init(date: Date(), number: 44, isInCurrentMonth: true, isToday: false),
                        .init(date: Date(), number: 43, isInCurrentMonth: true, isToday: false),
                        .init(date: Date(), number: 45, isInCurrentMonth: true, isToday: false),
                        .init(date: Date(), number: 44, isInCurrentMonth: true, isToday: false),
                        .init(date: Date(), number: 45, isInCurrentMonth: true, isToday: true),
                    ],
                ),
                monthNumber: 1,
                daySelectionManager: PCCalendarDaySelectionManager()
            ),
            cellSize: 50
        )
    }
}