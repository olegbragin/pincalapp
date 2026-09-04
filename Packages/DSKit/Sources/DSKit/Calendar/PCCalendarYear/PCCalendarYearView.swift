//
//  USCalendarYear.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI
import CoreDomain
import OrderedCollections

public struct PCCalendarYearView: View {
    @Bindable var viewModel: PCCalendarYearModel

    public init(viewModel: PCCalendarYearModel) {
        self.viewModel = viewModel
    }
    
    // Временный масштаб во время жеста (сбрасывается после)
    @GestureState private var tempMagnification: CGFloat = 1.0
    
    @State private var initialScrollIndex: Int?
    
    private static let monthColumnSpacing: CGFloat = 8
    private static let minMonthCellSize: CGFloat = 28
    private static let minMonthWidth: CGFloat = minMonthCellSize * 7
    
    private static func maxColumns(forWidth width: CGFloat) -> Int {
        max(3, Int(floor(width / minMonthWidth)))
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let cellSize = max(1, (proxy.size.width - Self.monthColumnSpacing * CGFloat(viewModel.internalNumberOfColumns - 1)) / CGFloat(viewModel.internalNumberOfColumns) / 7)
            ScrollView {
                LazyVGrid(
                    columns: gridColumns,
                    spacing: 16
                ) {
                    ForEach(viewModel.months.indices, id: \.self) { index in
                        let month = viewModel.months[index]
                        PCCalendarMonthView(
                            viewModel: month,
                            cellSize: cellSize
                        )
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $initialScrollIndex, anchor: .top)
            .onAppear {
                viewModel.maximumNumberOfColumns = Self.maxColumns(forWidth: proxy.size.width)
                setInitialScrollIndex()
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                viewModel.maximumNumberOfColumns = Self.maxColumns(forWidth: newWidth)
            }
            .onChange(of: viewModel.numberOfColumns) {
                initialScrollIndex = targetMonthIndex
            }
            .onChange(of: proxy.size) { oldSize, newSize in
                guard oldSize != newSize else { return }
                let target = initialScrollIndex ?? targetMonthIndex
                guard let target else { return }
                initialScrollIndex = nil
                Task { @MainActor in
                    initialScrollIndex = target
                }
            }
            .highPriorityGesture(pinchToZoomGesture)
            .animation(.easeOut(duration: 0.3), value: viewModel.numberOfColumns)
        }
    }
    
    private var pinchToZoomGesture: PCPinchToZoomGesture {
        PCPinchToZoomGesture(
            tempMagnification: $tempMagnification,
            onPinchedToZoomIn: {
                let next = viewModel.numberOfColumns + 1
                viewModel.numberOfColumns = min(viewModel.maximumNumberOfColumns, next)
            },
            onPinchedToZoomOut: {
                let next = viewModel.numberOfColumns - 1
                viewModel.numberOfColumns = max(1, next)
            }
        )
    }
    
    private static var columnsCache: [Int: [GridItem]] = [:]
    
    private var gridColumns: [GridItem] {
        let count = viewModel.internalNumberOfColumns
        if let cached = Self.columnsCache[count] {
            return cached
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.monthColumnSpacing), count: count)
        Self.columnsCache[count] = columns
        return columns
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

@MainActor
private func yearViewPreview() -> some View {
    let dataProvider = PCCalendarDataProvider()
    let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
    let yearModel = PCCalendarYearModel(
        numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
        numberOfColumns: 2
    )
    yearModel.months = dataProvider.months(forYear: year).map {
        PCCalendarMonthModel(dto: $0, daySelectionManager: PCCalendarDaySelectionManager())
    }
    return PCCalendarYearView(viewModel: yearModel)
}