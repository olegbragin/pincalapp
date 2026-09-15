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
    @Environment(\.pcVibe) private var vibe
    @State private var isYearPickerPresented = false
    
    var onLongPress: (() -> Void)?
    /// Invoked when the user picks a year. The feature layer rebuilds the month
    /// matrix for the chosen year and writes it into the model.
    var onYearSelect: ((Int) -> Void)?
    
    public static let yearRange: ClosedRange<Int> = 2000...2100
    
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
    
    public init(viewModel: PCCalendarYearModel, onLongPress: (() -> Void)? = nil, onYearSelect: ((Int) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onLongPress = onLongPress
        self.onYearSelect = onYearSelect
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            yearHeader
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
                        // The month rows are keyed by index (0...11), so replacing
                        // `months` with a new same-length array (e.g. when the year
                        // changes) leaves the ids unchanged and SwiftUI would reuse
                        // the stale rows. Rebinding the grid to the year forces it to
                        // rebuild against the newly generated month matrix.
                        .id(viewModel.year)
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
                    .onChange(of: viewModel.scrollTargetMonth) {
                        scrollToTargetMonth(using: scrollProxy)
                    }
                    .highPriorityGesture(
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
                    )
                    .simultaneousGesture(
                        LongPressGesture()
                            .onEnded { _ in
                                onLongPress?()
                            },
                        isEnabled: onLongPress != nil
                    )
                    // Horizontal swipe switches the year (left = next, right =
                    // previous). It runs simultaneously with the vertical scroll
                    // so swiping doesn't block scrolling or pinch-to-zoom; it only
                    // commits when the horizontal displacement dominates.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                let horizontal = abs(value.translation.width)
                                let vertical = abs(value.translation.height)
                                guard horizontal > vertical, horizontal > 50 else { return }
                                goToAdjacentYear(value.translation.width < 0 ? 1 : -1)
                            }
                    )
                    .sensoryFeedback(.success, trigger: viewModel.numberOfColumns)
                    .sensoryFeedback(.selection, trigger: viewModel.year)
                    .animation(.easeOut(duration: 0.3), value: viewModel.numberOfColumns)
                }
            }
        }
    }
    
    private var yearHeader: some View {
        HStack {
            Spacer()
            Button {
                isYearPickerPresented = true
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: String(viewModel.year))
                        .font(vibe.font(for: .yearTitle))
                        .foregroundColor(vibe.color(for: .foreground))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(vibe.color(for: .foregroundDisabled))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("year-select-button")
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .sheet(isPresented: $isYearPickerPresented) {
            PCYearPickerSheet(
                years: Array(Self.yearRange),
                selectedYear: viewModel.year,
                onSelect: { onYearSelect?($0) }
            )
        }
    }
    
    private func scrollToTargetMonth(using proxy: ScrollViewProxy) {
        guard let target = viewModel.targetMonthIndex else { return }
        proxy.scrollTo(target, anchor: .top)
    }

    ///// Switches to the adjacent year (delta of -1 or +1) on a horizontal swipe,
    ///// clamped to the supported year range. Reuses `onYearSelect` so the feature
    ///// layer's existing `switchYear` rebuilds the month matrix.
    private func goToAdjacentYear(_ delta: Int) {
        let next = viewModel.year + delta
        guard Self.yearRange.contains(next) else { return }
        onYearSelect?(next)
    }

    /// Scrolls to the current month of today's date after a pinch-to-zoom or a
    /// device/window rotation, so the user's focus stays on the current month.
    /// The scroll is deferred a tick so the grid re-layout (from the column /
    /// size change) settles first; otherwise the programmatic scroll is lost.
    private func scrollToCurrentMonth(using proxy: ScrollViewProxy) {
        guard let target = viewModel.targetMonthIndex else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
}

/// A sheet that lets the user pick a year from a range. The years are laid out
/// in an adaptive grid whose column count is derived from the available width so
/// the year labels always fit. Selecting a year dismisses the sheet.
private struct PCYearPickerSheet: View {
    let years: [Int]
    let selectedYear: Int
    let onSelect: (Int) -> Void
    @Environment(\.pcVibe) private var vibe
    @Environment(\.dismiss) private var dismiss

    private static let minColumnWidth: CGFloat = 84
    private static let columnSpacing: CGFloat = 12

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: gridColumns(forWidth: proxy.size.width),
                        spacing: Self.columnSpacing
                    ) {
                        ForEach(years, id: \.self) { year in
                            Button {
                                onSelect(year)
                                dismiss()
                            } label: {
                                Text(verbatim: String(year))
                                    .font(vibe.font(for: .yearButton))
                                    .foregroundColor(vibe.color(for: year == selectedYear ? .accent : .foreground))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(vibe.color(for: .background))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("year-option-\(year)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Выберите год")
            .pcNavigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func gridColumns(forWidth width: CGFloat) -> [GridItem] {
        let count = max(3, Int(floor(width / Self.minColumnWidth)))
        return Array(repeating: GridItem(.flexible(), spacing: Self.columnSpacing), count: count)
    }
}

#Preview {
    yearViewPreview()
}

@MainActor
private func yearViewPreview() -> some View {
    let daySelectionManager = PCCalendarDaySelectionManager()
    let yearModel = PCCalendarYearModel(numberOfCurrentMonth: 1, numberOfColumns: 2, year: 2026)
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
