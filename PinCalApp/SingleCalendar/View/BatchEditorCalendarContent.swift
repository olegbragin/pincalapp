//
//  BatchEditorCalendarContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct BatchEditorCalendarContent: View {
    var viewModel: USCalendarYearModel

    var body: some View {
        USCalendarYearView(viewModel: viewModel)
            .accessibilityIdentifier("batch-editor-calendar")
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
    return BatchEditorCalendarContent(viewModel: yearModel)
}
