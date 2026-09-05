//
//  SingleCalendarCalendarContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI
import DSKit
import CoreDomain

public struct SingleCalendarCalendarContent: View {
    public var isMultiSelect: Bool
    @Binding var selectedColor: PCColorOption?
    public var isColorPickerDisabled: Bool
    public var yearModel: PCCalendarYearDataSource

    public init(isMultiSelect: Bool, selectedColor: Binding<PCColorOption?>, isColorPickerDisabled: Bool, yearModel: PCCalendarYearDataSource) {
        self.isMultiSelect = isMultiSelect
        self._selectedColor = selectedColor
        self.isColorPickerDisabled = isColorPickerDisabled
        self.yearModel = yearModel
    }

    public var body: some View {
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
    SingleCalendarCalendarContentPreview()
}

@MainActor
private struct SingleCalendarCalendarContentPreview: View {
    private let yearModel: PCCalendarYearDataSource = {
        let dataProvider = PCCalendarDataProvider()
        let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
        let model = PCCalendarYearDataSource(
            numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
            numberOfColumns: 2
        )
        model.months = dataProvider.months(forYear: year).map {
            PCCalendarMonthModel(dto: $0, daySelectionManager: PCCalendarDaySelectionManager())
        }
        return model
    }()

    var body: some View {
        SingleCalendarCalendarContent(
            isMultiSelect: true,
            selectedColor: .constant(.option1),
            isColorPickerDisabled: false,
            yearModel: yearModel
        )
    }
}
