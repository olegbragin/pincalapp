//
//  USCalendarMonth.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI

struct USCalendarMonthView: View {
    @Bindable var viewModel: USCalendarMonthModel
    var cellSize: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.label)
                .padding(.leading, max(cellSize / 2 - 8, 2))
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                USCalendarWeekHeaderView(
                    viewModel: viewModel.weekHeaderModel,
                    cellSize: cellSize
                )
                ForEach(viewModel.weeks) { week in
                    USCalendarWeekView(
                        viewModel: week,
                        cellSize: cellSize
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
        ),
        cellSize: 50
    )
}
