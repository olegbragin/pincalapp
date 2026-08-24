import SwiftUI

struct CalendarListContent: View {
    @Environment(RootNavigation.self) var navigation

    @State private var focusedCardID: Int64?

    var calendars: [CalendarDataSource]
    var displayMode: DisplayMode
    var isArchived: Bool
    var cardViewModelFactory: (CalendarDataSource) -> PCCalendarCardViewModel
    var onCalendarDelete: (CalendarDataSource) -> Void
    var onCalendarRestore: (CalendarDataSource) -> Void
    var onCalendarPermanentDelete: (CalendarDataSource) -> Void
    var onRefresh: () async -> Void
    
    private var columns: [GridItem] {
        switch displayMode {
        case .list: return [GridItem(.flexible(), spacing: 12)]
        case .grid: return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
    }
    
    var body: some View {
        @Bindable var bindableRouter = navigation
        if calendars.isEmpty {
            CalendarEmptyStateView(isArchived: isArchived)
        } else {
            ZStack {
                    List(selection: $bindableRouter.selectedRoute) {
                        ForEach(calendars) { calendar in
                            EmptyView()
                                .tag(AppRoute.calendarDetail(calendar.id))
                        }
                    }
                    .hidden()

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(calendars) { calendar in
                                let viewModel = cardViewModelFactory(calendar)
                                let isSelected = navigation.selectedRoute == .calendarDetail(calendar.id)

                                PCCalendarCardView(
                                    viewModel: viewModel,
                                    onNameFieldFocusedChanged: { id, focused in
                                        focusedCardID = focused ? id : nil
                                    }
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
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        navigation.selectedRoute = .calendarDetail(calendar.id)
                                    }
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
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .refreshable {
                    await onRefresh()
                }
                .scrollDismissesKeyboard(.interactively)
                .keyboardAvoidable(focusedItem: $focusedCardID)
                .onChange(of: navigation.selectedRoute) { _, _ in
                    // navigation.path = NavigationPath()
                }
            }
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
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
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
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
        onCalendarDelete: { _ in },
        onCalendarRestore: { _ in },
        onCalendarPermanentDelete: { _ in },
        onRefresh: {}
    )
    .environment(PCKeyboardState())
}
