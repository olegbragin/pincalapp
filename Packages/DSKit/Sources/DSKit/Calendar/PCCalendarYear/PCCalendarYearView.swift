//
//  USCalendarYear.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI
import OrderedCollections

public struct PCCalendarYearView: View {
    @Bindable var viewModel: PCCalendarYearModel
    // Временный масштаб во время жеста (сбрасывается после)
    @GestureState private var tempMagnification: CGFloat = 1.0
    
    var onLongPress: (() -> Void)?
    
    private static let monthColumnSpacing: CGFloat = 8
    private static let minMonthCellSize: CGFloat = 28
    private static let minMonthWidth: CGFloat = minMonthCellSize * 7
    
    private static func maxColumns(forWidth width: CGFloat) -> Int {
        // Allow the column count to scale down with the available width. The
        // previous hard `3` floor forced tiny, hard-to-tap day cells (≈17pt)
        // whenever the split-view detail column was narrow, and the reported
        // frames of those micro-cells didn't line up with the actual hit
        // regions — making day taps land on the wrong (adjacent-month) cell.
        max(3, Int(floor(width / minMonthWidth)))
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
        let count = viewModel.numberOfColumns
        if let cached = Self.columnsCache[count] {
            return cached
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.monthColumnSpacing), count: count)
        Self.columnsCache[count] = columns
        return columns
    }
    
    public init(viewModel: PCCalendarYearModel, onLongPress: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onLongPress = onLongPress
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let cellSize = max(1, (proxy.size.width - Self.monthColumnSpacing * CGFloat(viewModel.numberOfColumns - 1)) / CGFloat(viewModel.numberOfColumns) / 7)
            ScrollViewReader { scrollProxy in
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
                .onAppear {
                    viewModel.maximumNumberOfColumns = Self.maxColumns(forWidth: proxy.size.width)
                    scrollToTargetMonth(using: scrollProxy)
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    viewModel.maximumNumberOfColumns = Self.maxColumns(forWidth: newWidth)
                }
                .onChange(of: viewModel.numberOfColumns) {
                    scrollToCurrentMonth(using: scrollProxy)
                }
                .onChange(of: proxy.size) { oldSize, newSize in
                    guard oldSize != newSize else { return }
                    scrollToCurrentMonth(using: scrollProxy)
                }
                .highPriorityGesture(pinchToZoomGesture)
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { _ in
                            onLongPress?()
                        },
                    isEnabled: onLongPress != nil
                )
                .sensoryFeedback(.success, trigger: viewModel.numberOfColumns)
                .animation(.easeOut(duration: 0.3), value: viewModel.numberOfColumns)
            }
        }
    }
    
    private func scrollToTargetMonth(using proxy: ScrollViewProxy) {
        guard let target = viewModel.targetMonthIndex else { return }
        proxy.scrollTo(target, anchor: .top)
    }

    /// Scrolls to the current month of today's date after a pinch-to-zoom or a
    /// device/window rotation, so the user's focus stays on the current month.
    /// The scroll is deferred a tick so the grid re-layout (from the column /
    /// size change) settles first; otherwise the programmatic scroll is lost.
    private func scrollToCurrentMonth(using proxy: ScrollViewProxy) {
        guard let target = viewModel.indexOfCurrentMonth else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
}

#Preview {
    yearViewPreview()
}

@MainActor
private func yearViewPreview() -> some View {
    let daySelectionManager = PCCalendarDaySelectionManager()
    let yearModel = PCCalendarYearModel(numberOfCurrentMonth: 1, numberOfColumns: 2)
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    yearModel.months = (1...3).map { monthNumber in
        let weeks = (0..<6).map { weekIndex in
            let days = (0..<7).map { dayIndex in
                let index = weekIndex * 7 + dayIndex
                return PCCalendarDayModel(
                    date: base.addingTimeInterval(TimeInterval(index * 86400)),
                    number: (index % 31) + 1,
                    isInCurrentMonth: true,
                    isToday: false,
                    gridMonth: monthNumber
                )
            }
            return PCCalendarWeekModel(days: days, daySelectionManager: daySelectionManager)
        }
        return PCCalendarMonthModel(
            number: monthNumber,
            label: "Month \(monthNumber)",
            weekDaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
            weeks: weeks
        )
    }
    return PCCalendarYearView(viewModel: yearModel)
}
