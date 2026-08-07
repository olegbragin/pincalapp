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
    
    var body: some View {
        ScrollViewReader { proxy in
            verticalLayout(proxy: proxy)
        }
    }
    
    private func verticalLayout(proxy: ScrollViewProxy) -> some View {
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
        }
        .onAppear {
            scrollToCurrentMonth(proxy: proxy, anchor: .top)
        }
        .onChange(of: viewModel.numberOfColumns) {
            scrollToCurrentMonth(proxy: proxy, anchor: .top)
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
    
    private func scrollToCurrentMonth(proxy: ScrollViewProxy, anchor: UnitPoint) {
        guard let index = viewModel.indexOfCurrentMonth else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proxy.scrollTo(index, anchor: anchor)
        }
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
