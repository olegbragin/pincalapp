//
//  BatchEditorCalendarContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI
import DSKit
import CoreDomain

public struct BatchEditorCalendarContent: View {
    public var viewModel: PCCalendarYearModel

    public init(viewModel: PCCalendarYearModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        PCCalendarYearView(viewModel: viewModel)
            .accessibilityIdentifier("batch-editor-calendar")
    }
}

#Preview {
    BatchEditorCalendarContentPreview()
}

@MainActor
private struct BatchEditorCalendarContentPreview: View {
    private let yearModel: PCCalendarYearModel = {
        let dataProvider = PCCalendarDataProvider()
        let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
        let model = PCCalendarYearModel(
            numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
            numberOfColumns: 2
        )
        model.months = dataProvider.months(forYear: year).map {
            PCCalendarMonthModel(dto: $0, daySelectionManager: PCCalendarDaySelectionManager())
        }
        return model
    }()

    var body: some View {
        BatchEditorCalendarContent(viewModel: yearModel)
    }
}
