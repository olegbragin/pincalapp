//
//  SingleCalendarCalendarContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct SingleCalendarCalendarContent: View {
    var isMultiSelect: Bool
    @Binding var selectedColor: ColorOption?
    var isColorPickerDisabled: Bool
    var yearModel: USCalendarYearModel

    var body: some View {
        VStack(spacing: 0) {
            if isMultiSelect {
                ExpandedColorPicker(selectedColor: $selectedColor)
                    .disabled(isColorPickerDisabled)
            }
            USCalendarYearView(viewModel: yearModel)
        }
    }
}

#Preview {
    let dataProvider = USCalendarDataProvider()
    let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
    let yearModel = USCalendarYearModel(
        numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
        numberOfColumns: 2
    )
    yearModel.months = dataProvider.months(forYear: year).map {
        USCalendarMonthModel(dto: $0, daySelectionManager: USCalendarDaySelectionManager())
    }
    return SingleCalendarCalendarContent(
        isMultiSelect: true,
        selectedColor: .constant(.option1),
        isColorPickerDisabled: false,
        yearModel: yearModel
    )
}
