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
            Group {
                switch viewModel.scrollDirection {
                case .vertical:
                    verticalLayout(proxy: proxy)
                case .horizontal:
                    horizontalLayout(proxy: proxy)
                }
            }
        }
    }
    
    private func verticalLayout(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: viewModel.internalNumberOfColumns
                ),
                spacing: 32
            ) {
                ForEach(viewModel.months.indices, id: \.self) { index in
                    let month = viewModel.months[index]
                    USCalendarMonthView(
                        viewModel: month
                    )
                    .id(index)
                }
            }
            .padding(16)
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
    
    private func horizontalLayout(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 32) {
                ForEach(viewModel.monthRows.indices, id: \.self) { rowIndex in
                    let row = viewModel.monthRows[rowIndex]
                    HStack(spacing: 12) {
                        ForEach(row.indices, id: \.self) { monthIndex in
                            let month = row[monthIndex]
                            USCalendarMonthView(
                                viewModel: month
                            )
                            .containerRelativeFrame(
                                [.horizontal, .vertical],
                                count: viewModel.internalNumberOfColumns,
                                spacing: 12
                            )
                            .id(month.id)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(rowIndex)
                }
            }
            .scrollTargetLayout()
            .padding(16)
        }
        .scrollTargetBehavior(.viewAligned)
        .onAppear {
            scrollToCurrentMonthRow(proxy: proxy)
        }
        .onChange(of: viewModel.numberOfColumns) {
            scrollToCurrentMonthRow(proxy: proxy)
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
    
    private func scrollToCurrentMonthRow(proxy: ScrollViewProxy) {
        guard let index = viewModel.indexOfCurrentMonth else { return }
        let rowIndex = index / max(1, viewModel.internalNumberOfColumns)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proxy.scrollTo(rowIndex, anchor: .leading)
        }
    }
}

#Preview("Vertical") {
    yearViewPreview(scrollDirection: .vertical)
}

#Preview("Horizontal") {
    yearViewPreview(scrollDirection: .horizontal)
}

private func yearViewPreview(
    scrollDirection: USCalendarYearModel.ScrollDirection
) -> some View {
    let dataProvider = USCalendarDataProvider()
    let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
    let yearModel = USCalendarYearModel(
        numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
        numberOfColumns: 3,
        scrollDirection: scrollDirection
    )
    yearModel.months = dataProvider.months(forYear: year).map {
        USCalendarMonthModel(dto: $0, daySelectionManager: USCalendarDaySelectionManager())
    }
    return USCalendarYearView(viewModel: yearModel)
}
