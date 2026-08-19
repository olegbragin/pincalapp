//
//  SingleCalendarCalendarContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct SingleCalendarCalendarContent: View {
    var isMultiSelect: Bool
    @Binding var selectedColor: PCColorOption?
    var isColorPickerDisabled: Bool
    var yearModel: PCCalendarYearModel

    var body: some View {
        VStack(spacing: 0) {
            if isMultiSelect {
                PCExpandedColorPicker(selectedColor: $selectedColor)
                    .disabled(isColorPickerDisabled)
            }
            PCCalendarYearView(viewModel: yearModel)
        }
    }
}

#Preview {
    let dataProvider = PCCalendarDataProvider()
    let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
    let yearModel = PCCalendarYearModel(
        numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
        numberOfColumns: 2
    )
    yearModel.months = dataProvider.months(forYear: year).map {
        PCCalendarMonthModel(dto: $0, daySelectionManager: PCCalendarDaySelectionManager())
    }
    return SingleCalendarCalendarContent(
        isMultiSelect: true,
        selectedColor: .constant(.option1),
        isColorPickerDisabled: false,
        yearModel: yearModel
    )
}
