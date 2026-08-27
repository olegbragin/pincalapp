import SwiftUI
import CorePersistence
import DSKit

public struct CalendarListContent: View {
    @State private var focusedCardID: Int64?

    public var calendars: [CalendarDataSource]
    public var displayMode: DisplayMode
    public var isArchived: Bool
    public var cardViewModelFactory: (CalendarDataSource) -> PCCalendarCardViewModel
    public var onCalendarDelete: (CalendarDataSource) -> Void
    public var onCalendarRestore: (CalendarDataSource) -> Void
    public var onCalendarPermanentDelete: (CalendarDataSource) -> Void
    public var onRefresh: () async -> Void
    public var selectedCalendarID: Int64?
    public var onSelectCalendar: (Int64) -> Void = { _ in }

    public init(
        calendars: [CalendarDataSource],
        displayMode: DisplayMode,
        isArchived: Bool,
        cardViewModelFactory: @escaping (CalendarDataSource) -> PCCalendarCardViewModel,
        onCalendarDelete: @escaping (CalendarDataSource) -> Void,
        onCalendarRestore: @escaping (CalendarDataSource) -> Void,
        onCalendarPermanentDelete: @escaping (CalendarDataSource) -> Void,
        onRefresh: @escaping () async -> Void,
        selectedCalendarID: Int64? = nil,
        onSelectCalendar: @escaping (Int64) -> Void = { _ in }
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
    }
    
    private var columns: [GridItem] {
        switch displayMode {
        case .list: return [GridItem(.flexible(), spacing: 12)]
        case .grid: return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
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
                            onNameFieldFocusedChanged: { id, focused in
                                focusedCardID = focused ? id : nil
                            },
                            nameFieldFocused: false
                        )
                        .id(calendar.id)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: isSelected ? 2.5 : 0
                                )
                        )
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: isSelected ? 8 : 0)
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
                                    Label("Restore", systemImage: "arrow.counterclockwise")
                                }
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        onCalendarPermanentDelete(calendar)
                                    }
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash")
                                }
                            } else {
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        onCalendarDelete(calendar)
                                    }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .refreshable {
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
            CalendarDataSource(id: 1, name: "My Calendar", year: 2026, numberOfColumns: 3),
            CalendarDataSource(id: 2, name: "Work", year: 2026, numberOfColumns: 2)
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
