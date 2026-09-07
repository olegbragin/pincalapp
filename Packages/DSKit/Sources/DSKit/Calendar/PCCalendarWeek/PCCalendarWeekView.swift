//
//  SwiftUIView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI

public struct PCCalendarWeekView: View {
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
            }
        }
    }
}

#Preview {
    let daySelectionManager = PCCalendarDaySelectionManager()
    let days = [
        PCCalendarDayModel(date: Date(), number: 44, isInCurrentMonth: true, isToday: false, gridMonth: 1),
        PCCalendarDayModel(date: Date(), number: 43, isInCurrentMonth: true, isToday: false, gridMonth: 1),
        PCCalendarDayModel(date: Date(), number: 44, isInCurrentMonth: true, isToday: false, gridMonth: 1),
        PCCalendarDayModel(date: Date(), number: 43, isInCurrentMonth: true, isToday: false, gridMonth: 1),
        PCCalendarDayModel(date: Date(), number: 45, isInCurrentMonth: true, isToday: false, gridMonth: 1),
        PCCalendarDayModel(date: Date(), number: 44, isInCurrentMonth: true, isToday: false, gridMonth: 1),
        PCCalendarDayModel(date: Date(), number: 45, isInCurrentMonth: true, isToday: true, gridMonth: 1),
    ]
    return Grid {
        PCCalendarWeekView(
            viewModel: PCCalendarWeekModel(days: days, daySelectionManager: daySelectionManager),
            cellSize: 50
        )
    }
}