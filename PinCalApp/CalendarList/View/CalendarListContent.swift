import SwiftUI

struct CalendarListContent: View {
    @Environment(RootNavigation.self) var navigation
    
    var calendars: [CalendarDataSource]
    var displayMode: DisplayMode
    var cardViewModelFactory: (CalendarDataSource) -> PCCalendarCardViewModel
    var onCalendarDelete: (CalendarDataSource) -> Void
    var onRefresh: () async throws -> Void
    
    private var columns: [GridItem] {
        switch displayMode {
        case .list: return [GridItem(.flexible(), spacing: 12)]
        case .grid: return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
    }
    
    var body: some View {
        if calendars.isEmpty {
            CalendarEmptyStateView()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(calendars) { calendar in
                        let viewModel = cardViewModelFactory(calendar)
                        let isSelected = navigation.selectedRoute == .calendarDetail(calendar.id)
                        
                        PCCalendarCardView(viewModel: viewModel)
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
                                Button(role: .destructive) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        onCalendarDelete(calendar)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .refreshable {
                try? await onRefresh()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: navigation.selectedRoute) { _, _ in
                navigation.path = NavigationPath()
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
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
        onCalendarDelete: { _ in },
        onRefresh: {}
    )
}

#Preview("Empty") {
    CalendarListContent(
        calendars: [],
        displayMode: .list,
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
        onCalendarDelete: { _ in },
        onRefresh: {}
    )
}
