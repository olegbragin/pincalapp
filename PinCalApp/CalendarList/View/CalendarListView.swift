//
//  CalendarListView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 09.02.2026.
//

import SwiftUI

struct CalendarListView: View {
    @Binding var navigation: RootNavigation
    @State private var viewModel = CalendarListViewModel()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            CalendarListContent(
                calendars: viewModel.calendars,
                cardViewModelFactory: { viewModel.cardViewModel(for: $0) },
                onCalendarTap: { navigation.selectedItem = .calendar(id: $0.id) },
                onCalendarDelete: { viewModel.removeCalendarFromList($0) },
                onRefresh: { try await viewModel.fetch() }
            )

            Text(viewModel.appVersion)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.isAnyCardEditing {
                Button(action: viewModel.addItem) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                }
                .pcGlass(cornerRadius: 28)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("My calendars")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.hasPendingChanges {
                    Menu {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) {
                                viewModel.undoLastChange()
                            }
                        } label: {
                            Label("Undo Last", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                viewModel.undoAllChanges()
                            }
                        } label: {
                            Label("Undo All", systemImage: "arrow.uturn.backward.circle")
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
        }
        .task {
            try? await viewModel.fetch()
        }
        .onChange(of: viewModel.addEditCalendarViewModel.calendar) {
            if $0 != $1, let calendar = $1 {
                viewModel.addCalendar(with: calendar.name)
            }
        }
        .sheet(isPresented: $viewModel.isAddEditSheetPresented) {
            AddEditCalendarView(viewModel: viewModel.addEditCalendarViewModel)
        }
        .compactCalendarNavigationDestination(
            isCompact: horizontalSizeClass == .compact,
            item: selectedItemBinding
        )
    }

    private var selectedItemBinding: Binding<RootSelection?> {
        Binding(
            get: { navigation.selectedItem },
            set: { navigation.selectedItem = $0 }
        )
    }
}

private extension View {
    @ViewBuilder
    func compactCalendarNavigationDestination(
        isCompact: Bool,
        item: Binding<RootSelection?>
    ) -> some View {
        if isCompact {
            navigationDestination(item: item) { selection in
                if case .calendar(let id) = selection {
                    CalendarDetailView(calendarId: id)
                }
            }
        } else {
            self
        }
    }
}
