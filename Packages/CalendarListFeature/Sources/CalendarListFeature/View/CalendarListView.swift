import SwiftUI
import CoreDomain
import DSKit

public struct CalendarListView: View {
    @Environment(\.calendarManaging) private var managing
    @State private var viewModel: CalendarListViewModel?
    @State private var isAddSheetPresented = false
    public var selectedCalendarID: Int64?
    public var onSelectCalendar: (Int64) -> Void = { _ in }
    let mode: CalendarListMode

    /// How long the undo toast stays up. See `CalendarListViewModel.undoWindowDuration`.
    let undoWindowDuration: TimeInterval

    public init(
        mode: CalendarListMode = .active,
        selectedCalendarID: Int64? = nil,
        onSelectCalendar: @escaping (Int64) -> Void = { _ in },
        undoWindowDuration: TimeInterval = 5
    ) {
        self.mode = mode
        self.selectedCalendarID = selectedCalendarID
        self.onSelectCalendar = onSelectCalendar
        self.undoWindowDuration = undoWindowDuration
    }

    public var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                PCProgressView(label: "Loading")
            }
        }
        .task {
            if viewModel == nil {
                guard let managing else { return }
                viewModel = CalendarListViewModel(mode: mode, managing: managing, undoWindowDuration: undoWindowDuration)
            }
            await viewModel?.fetch()
        }
    }

    @ViewBuilder
    private func content(for model: CalendarListViewModel) -> some View {
        // The `@Sendable` refresh closure below must capture the immutable parameter,
        // not this `@Bindable` shadow, which is a `var` the compiler rightly refuses to
        // let escape into concurrent code.
        @Bindable var viewModel = model
        VStack(spacing: 0) {
            if viewModel.isLoading, viewModel.calendars.isEmpty {
                Spacer()
                PCProgressView(label: "Loading")
                Spacer()
            } else {
                CalendarListContent(
                    calendars: viewModel.calendars,
                    displayMode: viewModel.displayMode,
                    isArchived: mode == .archived,
                    cardViewModelFactory: { viewModel.cardViewModel(for: $0) },
                    onCalendarDelete: { viewModel.archiveCalendarInList($0) },
                    onCalendarRestore: { viewModel.restoreCalendarInList($0) },
                    onCalendarPermanentDelete: { viewModel.permanentlyDeleteCalendar($0) },
                    onRefresh: { await model.fetch() },
                    selectedCalendarID: selectedCalendarID,
                    onSelectCalendar: onSelectCalendar
                )
            }

            Text(viewModel.appVersion)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .background(PCSystemColor.systemGroupedBackground)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.isAnyCardEditing, mode == .active {
                Button {
                    viewModel.addItem()
                    isAddSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
                        .frame(width: 56, height: 56)
                }
                .pcGlass(cornerRadius: 28, tint: .black.opacity(0.22))
                .clipShape(Circle())
                // The route to "there are no calendars, so make one". It is a symbol with no
                // text, so without an identifier there is nothing stable to find it by.
                .accessibilityIdentifier("calendar-list-add-button")
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .pcNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(mode == .active ? "My calendars" : "Archived")
                    .font(.headline)
            }
            ToolbarItem(placement: .pcTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.displayMode = viewModel.displayMode.toggled
                    }
                } label: {
                    Label(viewModel.displayMode.toggled.label, systemImage: viewModel.displayMode.toggled.icon)
                }
            }
        }
        .onChange(of: viewModel.addEditCalendarViewModel.calendar) {
            if $0 != $1, let calendar = $1 {
                viewModel.addCalendar(with: calendar.name)
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddEditCalendarView(viewModel: viewModel.addEditCalendarViewModel)
        }
        .pcToast(
            isPresented: $viewModel.isArchiveToastPresented,
            position: .bottom,
            message: viewModel.archiveToastMessage,
            actionTitle: "Undo",
            action: { viewModel.undoArchive() },
            backgroundColor: .black.opacity(0.85),
            progress: viewModel.archiveToastProgress,
            // Named, so a test presses *Undo* rather than tapping the toast body and hoping
            // it landed on the right third of it.
            identifier: "archive-undo-toast",
            actionIdentifier: "archive-undo-toast-button"
        )
    }
}
