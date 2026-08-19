//
//  CalendarListContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct CalendarListContent: View {
    var calendars: [CalendarDataSource]
    var cardViewModelFactory: (CalendarDataSource) -> PCCalendarCardViewModel
    var onCalendarTap: (CalendarDataSource) -> Void
    var onCalendarDelete: (CalendarDataSource) -> Void
    var onRefresh: () async throws -> Void

    var body: some View {
        if calendars.isEmpty {
            CalendarEmptyStateView()
        } else {
            List {
                ForEach(calendars) { calendar in
                    PCCalendarCardView(
                        viewModel: cardViewModelFactory(calendar)
                    ) {
                        onCalendarTap(calendar)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
            .scrollContentBackground(.hidden)
            .refreshable {
                try? await onRefresh()
            }
            .scrollDismissesKeyboard(.interactively)
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
        onCalendarTap: { _ in },
        onCalendarDelete: { _ in },
        onRefresh: {}
    )
}

#Preview("Empty") {
    CalendarListContent(
        calendars: [],
        cardViewModelFactory: { PCCalendarCardViewModel(calendar: $0) },
        onCalendarTap: { _ in },
        onCalendarDelete: { _ in },
        onRefresh: {}
    )
}
