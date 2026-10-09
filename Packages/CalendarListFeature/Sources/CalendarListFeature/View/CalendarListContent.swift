
import SwiftUI
import CoreDomain
import DSKit

public struct CalendarListContent: View {
    @State private var focusedCardID: Int64?

    public var calendars: [PinCalendar]
    public var displayMode: DisplayMode
    public var isArchived: Bool
    public var cardViewModelFactory: (PinCalendar) -> PCCalendarCardViewModel
    public var onCalendarDelete: (PinCalendar) -> Void
    public var onCalendarRestore: (PinCalendar) -> Void
    public var onCalendarPermanentDelete: (PinCalendar) -> Void
    /// `@Sendable` because the pull-to-refresh gesture fires it from a `Task` that
    /// `PCSafeRefreshableModifier` owns.
    public var onRefresh: @Sendable () async -> Void
    public var selectedCalendarID: Int64?
    public var onSelectCalendar: (Int64) -> Void = { _ in }

    /// Which card to draw. `.compact` is for the collapsed landscape rail; see `PCCardLayout`.
    ///
    /// Named `cardLayout` rather than `layout`: `layout` reads as SwiftUI's own layout
    /// vocabulary, and naming it that made the type-checker fail on the `ForEach` below with an
    /// error about `Range<Int>` that had nothing to do with either.
    public var cardLayout: PCCardLayout

    public init(
        calendars: [PinCalendar],
        displayMode: DisplayMode,
        isArchived: Bool,
        cardViewModelFactory: @escaping (PinCalendar) -> PCCalendarCardViewModel,
        onCalendarDelete: @escaping (PinCalendar) -> Void,
        onCalendarRestore: @escaping (PinCalendar) -> Void,
        onCalendarPermanentDelete: @escaping (PinCalendar) -> Void,
        onRefresh: @escaping @Sendable () async -> Void,
        selectedCalendarID: Int64? = nil,
        onSelectCalendar: @escaping (Int64) -> Void = { _ in },
        cardLayout: PCCardLayout = .full
    ) {
        self.calendars = calendars
        self.displayMode = displayMode
        self.isArchived = isArchived
        self.cardViewModelFactory = cardViewModelFactory
        self.onCalendarDelete = onCalendarDelete
        self.onCalendarRestore = onCalendarRestore
        self.onCalendarPermanentDelete = onCalendarPermanentDelete
        self.onRefresh = onRefresh
        self.selectedCalendarID = selectedCalendarID
        self.onSelectCalendar = onSelectCalendar
        self.cardLayout = cardLayout
    }

    /// One column when compact.
    ///
    /// The grid's second column would put two cards side by side in a 66pt rail, which is 33pt
    /// each — narrower than the compact card's own text can render.
    /// The selection ring's corner radius, matching the card it is drawn around.
    ///
    /// Was hard-coded to 20 while the compact card draws at 10, so on the collapsed rail the
    /// ring floated outside its card with visibly rounder corners. Two literals in two files had
    /// to agree and nothing made them.
    private var cardCornerRadius: CGFloat {
        cardLayout == .compact ? 10 : 20
    }

    private var columns: [GridItem] {
        switch displayMode {
        case .list:
            return [GridItem(.flexible(), spacing: 12)]
        case .grid:
            guard cardLayout == .compact else {
                return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            }
            // One column in the collapsed rail: a second would put two cards side by side in
            // 66pt, which is 33pt each — narrower than the compact card's own text renders.
            return [GridItem(.flexible(), spacing: 12)]
        }
    }

    public var body: some View {
        if calendars.isEmpty {
            CalendarEmptyStateView(isArchived: isArchived)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(calendars) { calendar in
                        let viewModel = cardViewModelFactory(calendar)
                        let isSelected = selectedCalendarID == calendar.id

                        PCCalendarCardView(
                            viewModel: viewModel,
                            // `DSKit` names nothing itself, so the feature that owns this screen
                            // supplies the card's words. `columns` is built here rather than inside
                            // the card because the count is the card's data and the sentence is
                            // this feature's — the card takes both finished.
                            archivedLabel: String(localized: .archived),
                            columnsLabel: String(
                                format: String(localized: .columns(viewModel.numberOfColumns)),
                                viewModel.numberOfColumns
                            ),
                            namePlaceholder: String(localized: .calendarName),
                            onNameFieldFocusedChanged: { id, focused in
                                focusedCardID = focused ? id : nil
                            },
                            nameFieldFocused: false,
                            layout: cardLayout
                        )
                        .id(calendar.id)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: isSelected ? 2.5 : 0
                                )
                        )
                        .animation(.easeOut(duration: 0.2), value: isSelected)
                        .onTapGesture {
                            onSelectCalendar(calendar.id)
                        }
                        .contextMenu {
                            if calendar.isArchived {
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        onCalendarRestore(calendar)
                                    }
                                } label: {
                                    Label(.restore, systemImage: "arrow.counterclockwise")
                                }
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        onCalendarPermanentDelete(calendar)
                                    }
                                } label: {
                                    Label(.deletePermanently, systemImage: "trash")
                                }
                            } else {
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        onCalendarDelete(calendar)
                                    }
                                } label: {
                                    Label(.archive, systemImage: "archivebox")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, cardLayout == .compact ? 8 : 16)
            .padding(.top, 12)
            // `safeRefreshable`, not `.refreshable`: plain `.refreshable` on a
            // ScrollView is the thing that misbehaves on iOS 26+ (contentOffset
            // jumps), which is what PCSafeRefreshableModifier exists to work around.
            .safeRefreshable {
                await onRefresh()
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardAvoidable(focusedItem: $focusedCardID)
        }
    }
}

#Preview("With Calendars") {
    CalendarListContent(
        calendars: [
            PinCalendar(id: 1, name: "My Calendar", year: 2026, numberOfColumns: 3),
            PinCalendar(id: 2, name: "Work", year: 2026, numberOfColumns: 2),
        ],
        displayMode: .grid,
        isArchived: false,
        cardViewModelFactory: { PCCalendarCardViewModel(id: $0.id, name: $0.name, numberOfColumns: $0.numberOfColumns, isArchived: $0.isArchived) },
        onCalendarDelete: { _ in },
        onCalendarRestore: { _ in },
        onCalendarPermanentDelete: { _ in },
        onRefresh: {}
    )
    .environment(PCKeyboardState())
}

#Preview("Empty") {
    CalendarListContent(
        calendars: [],
        displayMode: .list,
        isArchived: false,
        cardViewModelFactory: { PCCalendarCardViewModel(id: $0.id, name: $0.name, numberOfColumns: $0.numberOfColumns, isArchived: $0.isArchived) },
        onCalendarDelete: { _ in },
        onCalendarRestore: { _ in },
        onCalendarPermanentDelete: { _ in },
        onRefresh: {}
    )
    .environment(PCKeyboardState())
}
