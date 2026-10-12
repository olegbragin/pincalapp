//
//  PCCalendarYearView.swift
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

    /// Which month row is at the top of the year grid, as an index into `viewModel.months`.
    ///
    /// Doubles as an input and an output: writing it scrolls, and SwiftUI writes back
    /// whichever row the user actually scrolls to. The write-back is why the column and size
    /// observers below re-assign `viewModel.targetMonthIndex` rather than trusting the stored
    /// value — after the user scrolls away, this holds where they *are*, not where the calendar
    /// wants them.
    @State private var scrollPosition: Int?

    /// The year-picker sheet's navigation title, supplied by the caller.
    ///
    /// Required, not defaulted: `DSKit` does not localize, so there is no word here that would be
    /// right for every language. The year *numbers* need no such treatment — `String(year)` is the
    /// same in all of them, and the month and weekday labels already arrive through the model.
    public let selectYearTitle: String

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

    /// Column layouts by count. The only mutable static in the package, so it is worth saying why it
    /// is safe: `DSKit` builds in Swift 6 language mode, where a nonisolated mutable static is a
    /// compile error, and this one compiles. The type inherits `@MainActor` from its `View`
    /// conformance, so both the read and the write below are main-actor isolated and the
    /// unsynchronised `Dictionary` cannot be reached from two threads at once.
    ///
    /// That safety is a property of the isolation, not of the declaration — a `nonisolated` call
    /// site added later would reintroduce a data race here with no local signal. If this ever has
    /// to be read off the main actor, make it a `nonisolated let` built once instead of adding a
    /// lock; the value is a pure function of `count`.
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

    public init(
        viewModel: PCCalendarYearModel,
        selectYearTitle: String,
        onLongPress: (() -> Void)? = nil,
        onYearSelect: ((Int) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.selectYearTitle = selectYearTitle
        self.onLongPress = onLongPress
        self.onYearSelect = onYearSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            yearHeader
            GeometryReader { proxy in
                let cellSize = max(1, (proxy.size.width - Self.monthColumnSpacing * CGFloat(viewModel.numberOfColumns - 1)) / CGFloat(viewModel.numberOfColumns) / 7)
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
                // The scroll position is state, not an imperative `scrollTo`.
                //
                // This replaces four call sites against a `ScrollViewProxy`, two of which
                // deferred behind a 50ms sleep. The sleep existed because a `scrollTo`
                // issued *during* a relayout was being lost: the grid re-lays out when the
                // column count changes, and the old code fired its scroll 50ms into a 300ms
                // layout animation and hoped the two settled. Declaring the position makes
                // keeping that identity visible SwiftUI's job — it holds the position across
                // exactly the events that used to lose it, including the size changes and
                // rotation the `proxy.size` observer was watching for. So there is no longer
                // a moment to wait for, and no offset to guess.
                .scrollPosition(id: $scrollPosition, anchor: .top)
                .onAppear {
                    viewModel.maximumNumberOfColumns = Self.maxColumns(forWidth: proxy.size.width)
                    scrollPosition = viewModel.targetMonthIndex
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    viewModel.maximumNumberOfColumns = Self.maxColumns(forWidth: newWidth)
                }
                // Animated explicitly, as the old `scrollToCurrentMonth` was. Kept rather
                // than relying on the `.animation(_:value: numberOfColumns)` modifier below,
                // which is keyed to the column change and does not necessarily reach a
                // scroll-position write. Porting the mechanism that demonstrably worked
                // beats assuming a broader one also does.
                .onChange(of: viewModel.numberOfColumns) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollPosition = viewModel.targetMonthIndex
                    }
                }
                // No `oldSize != newSize` guard: `onChange(of:)` does not invoke its closure
                // when the tracked value is equal, so the check could never trip.
                .onChange(of: proxy.size) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollPosition = viewModel.targetMonthIndex
                    }
                }
                .onChange(of: viewModel.scrollTargetMonth) {
                    // Not animated, matching the old `scrollToTargetMonth` — which unlike
                    // `scrollToCurrentMonth` never wrapped its `scrollTo` in `withAnimation`.
                    // The distinction was incidental rather than chosen, but preserving it
                    // keeps this a pure refactor and nothing more.
                    scrollPosition = viewModel.targetMonthIndex
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
                // so swiping doesn't block scrolling or pinch-to-zoom. It only
                // commits on a clearly horizontal swipe (the horizontal
                // displacement must dominate by a wide margin and exceed a
                // larger threshold), so a near-vertical scroll or a
                // UI-test swipe can't accidentally change the year.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            guard horizontal > vertical * 2, horizontal > 70 else { return }
                            goToAdjacentYear(value.translation.width < 0 ? 1 : -1)
                        }
                )
                .sensoryFeedback(.success, trigger: viewModel.numberOfColumns)
                .sensoryFeedback(.selection, trigger: viewModel.year)
                .animation(.easeOut(duration: 0.3), value: viewModel.numberOfColumns)
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
                title: selectYearTitle,
                years: Array(Self.yearRange),
                selectedYear: viewModel.year,
                onSelect: { onYearSelect?($0) }
            )
        }
    }

    ///// Switches to the adjacent year (delta of -1 or +1) on a horizontal swipe,
    ///// clamped to the supported year range. Reuses `onYearSelect` so the feature
    ///// layer's existing `switchYear` rebuilds the month matrix.
    private func goToAdjacentYear(_ delta: Int) {
        let next = viewModel.year + delta
        guard Self.yearRange.contains(next) else { return }
        onYearSelect?(next)
    }
}

/// A sheet that lets the user pick a year from a range. The years are laid out
/// in an adaptive grid whose column count is derived from the available width so
/// the year labels always fit. Selecting a year dismisses the sheet.
private struct PCYearPickerSheet: View {
    let title: String
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
            .navigationTitle(title)
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
    return PCCalendarYearView(viewModel: yearModel, selectYearTitle: "Select year")
}
