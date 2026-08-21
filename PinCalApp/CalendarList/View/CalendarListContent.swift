import SwiftUI

struct CalendarListContent: View {
    @Environment(RootNavigation.self) var navigation
    
    var calendars: [CalendarDataSource]
    var cardViewModelFactory: (CalendarDataSource) -> PCCalendarCardViewModel
    var onCalendarDelete: (CalendarDataSource) -> Void
    var onRefresh: () async throws -> Void
    
    var body: some View {
        @Bindable var bindableRouter = navigation
        
        if calendars.isEmpty {
            CalendarEmptyStateView()
        } else {
            List(selection: $bindableRouter.selectedRoute) {
                ForEach(calendars) { calendar in
                    PCCalendarCardView(
                        viewModel: cardViewModelFactory(calendar)
                    )
                    .tag(AppRoute.calendarDetail(calendar.id))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing) {
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
            .listStyle(.plain)
            .background(.clear)
            .scrollContentBackground(.hidden)
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
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
        onCalendarDelete: { _ in },
        onRefresh: {}
    )
}

#Preview("Empty") {
    CalendarListContent(
        calendars: [],
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
        onCalendarDelete: { _ in },
        onRefresh: {}
    )
}
