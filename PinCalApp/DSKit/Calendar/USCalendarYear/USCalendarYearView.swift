//
//  USCalendarYear.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI
import OrderedCollections

struct USCalendarYearView: View {
    @Bindable var viewModel: USCalendarYearModel
    
    // Временный масштаб во время жеста (сбрасывается после)
    @GestureState private var tempMagnification: CGFloat = 1.0
    
    @State private var initialScrollIndex: Int?
    
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible()),
                    count: viewModel.internalNumberOfColumns
                )
            ) {
                ForEach(viewModel.months.indices, id: \.self) { index in
                    let month = viewModel.months[index]
                    USCalendarMonthView(
                        viewModel: month
                    )
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $initialScrollIndex, anchor: .top)
        .onAppear {
            setInitialScrollIndex()
        }
        .onChange(of: viewModel.numberOfColumns) {
            initialScrollIndex = targetMonthIndex
        }
        .highPriorityGesture(pinchToZoomGesture)
        .animation(.easeOut(duration: 0.3), value: viewModel.numberOfColumns)
    }
    
    private var pinchToZoomGesture: USCalendarPinchToZoomGesture {
        USCalendarPinchToZoomGesture(
            tempMagnification: $tempMagnification,
            numberOfColumns: $viewModel.numberOfColumns
        )
    }
    
    private func setInitialScrollIndex() {
        guard initialScrollIndex == nil else { return }
        initialScrollIndex = targetMonthIndex
    }
    
    private var targetMonthIndex: Int? {
        if let target = viewModel.scrollTargetDate {
            let monthNumber = Calendar.autoupdatingCurrent.component(.month, from: target)
            return viewModel.months.firstIndex { $0.number == monthNumber }
        }
        return viewModel.indexOfCurrentMonth
    }
}

#Preview {
    yearViewPreview()
}

private func yearViewPreview() -> some View {
    let dataProvider = USCalendarDataProvider()
    let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
    let yearModel = USCalendarYearModel(
        numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
        numberOfColumns: 2
    )
    yearModel.months = dataProvider.months(forYear: year).map {
        USCalendarMonthModel(dto: $0, daySelectionManager: USCalendarDaySelectionManager())
    }
    return USCalendarYearView(viewModel: yearModel)
}
