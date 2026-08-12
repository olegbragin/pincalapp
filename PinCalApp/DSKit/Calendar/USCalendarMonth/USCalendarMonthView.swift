//
//  USCalendarMonth.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI

struct USCalendarMonthView: View {
    @Bindable var viewModel: USCalendarMonthModel
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text(viewModel.label)
            LazyVStack(alignment: .leading, spacing: 0) {
                USCalendarWeekHeaderView(viewModel: .init(weekSymbols: viewModel.weekDaySymbols))
                    .padding(.bottom, 0)
                ForEach(viewModel.weeks) { week in
                    USCalendarWeekView(
                        viewModel: week
                    )
                }
            }
        }
    }
}

#Preview {
    USCalendarMonthView(
        viewModel: .init(
            dto: .init(
                number: 1,
                label: "Jan",
                weekDaySymbols: ["S"],
                weeks: []
            ),
            daySelectionManager: USCalendarDaySelectionManager()
        )
    )
}
