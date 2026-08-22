import SwiftUI

struct CalendarListView: View {
    @State private var viewModel: CalendarListViewModel

    init(mode: CalendarListMode = .active) {
        _viewModel = State(initialValue: CalendarListViewModel(mode: mode))
    }

    var body: some View {
        VStack(spacing: 0) {
            CalendarListContent(
                calendars: viewModel.calendars,
                displayMode: viewModel.displayMode,
                isArchived: viewModel.mode == .archived,
                cardViewModelFactory: { viewModel.cardViewModel(for: $0) },
                onCalendarDelete: { viewModel.archiveCalendarInList($0) },
                onCalendarRestore: { viewModel.restoreCalendarInList($0) },
                onCalendarPermanentDelete: { viewModel.permanentlyDeleteCalendar($0) },
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
            if !viewModel.isAnyCardEditing, viewModel.mode == .active {
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
                Text(viewModel.mode == .active ? "My calendars" : "Archived")
                    .font(.headline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.displayMode = viewModel.displayMode.toggled
                    }
                } label: {
                    Label(viewModel.displayMode.toggled.label, systemImage: viewModel.displayMode.toggled.icon)
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
    }
}
