//
//  BatchEditorCalendarContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct BatchEditorCalendarContent: View {
    var viewModel: PCCalendarYearModel

    var body: some View {
        PCCalendarYearView(viewModel: viewModel)
            .accessibilityIdentifier("batch-editor-calendar")
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
    return BatchEditorCalendarContent(viewModel: yearModel)
}
