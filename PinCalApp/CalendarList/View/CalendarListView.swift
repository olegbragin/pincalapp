//
//  CalendarListView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 09.02.2026.
//

import SwiftUI

struct CalendarListView: View {
    @Binding var selector: RootSelectionCoordinator
    @State private var viewModel = CalendarListViewModel()
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        VStack(spacing: 0) {
            cardDeck
            
            Text(appVersion)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            if viewModel.editingCalendarID == nil {
                Button(action: viewModel.addItem) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                }
                .dsGlass(cornerRadius: 28)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.hasPendingChanges {
                    Button {
                        viewModel.commitChanges()
                    } label: {
                        Image(systemName: "checkmark")
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
            get: { selector.selectedItem },
            set: { selector.selectedItem = $0 }
        )
    }
    
    private var cardDeck: some View {
        Group {
            if viewModel.calendars.isEmpty {
                emptyDeck
            } else {
                WalletCardStack(
                    items: deckItems,
                    onSelect: { calendar in
                        guard viewModel.editingCalendarID == nil else { return }
                        selector.selectedItem = .calendar(id: calendar.id)
                    },
                    onRemove: { calendar in
                        withAnimation(.easeOut(duration: 0.3)) {
                            viewModel.removeCalendarFromDeck(calendar)
                        }
                    },
                    onLongPress: { calendar in
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            viewModel.startEditing(calendar)
                        }
                    },
                    editingID: viewModel.editingCalendarID,
                    cardContent: { calendar, width, height, isEditing in
                        CalendarCardContent(
                            calendar: calendar,
                            width: width,
                            height: height,
                            isEditing: isEditing,
                            editingName: $viewModel.editingCalendarName,
                            gradient: Self.cardGradient(for: calendar.id),
                            onEdit: {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    viewModel.startEditing(calendar)
                                }
                            }
                        )
                    }
                )
                .safeRefreshable {
                    try? await viewModel.fetch()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
    
    private var emptyDeck: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text("Нет календарей. Нажмите «+», чтобы добавить.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var deckItems: [CalendarDataSource] {
        var items = Array(viewModel.calendars.reversed())
        
        if case .calendar(let selectedID)? = selector.selectedItem,
           let index = items.firstIndex(where: { $0.id == selectedID }) {
            let selected = items.remove(at: index)
            items.insert(selected, at: 0)
        }
        
        return items
    }

    
    private static func cardGradient(for id: Int64) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.82, green: 0.83, blue: 0.86),
                Color(red: 0.58, green: 0.60, blue: 0.63),
                Color(red: 0.42, green: 0.44, blue: 0.47)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private struct CalendarCardContent: View {
    let calendar: CalendarDataSource
    let width: CGFloat
    let height: CGFloat
    let isEditing: Bool
    @Binding var editingName: String
    let gradient: LinearGradient
    var onEdit: (() -> Void)?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(gradient)
            
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                    Text(calendar.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    if isEditing {
                        Text("Editing")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    } else if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text("Columns: \(calendar.numberOfColumns)")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.7)
                    .padding(.top, 2)
                
                Spacer(minLength: 0)
                
                if isEditing {
                    TextField("Calendar name", text: $editingName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.15))
                        )
                } else {
                    Text(calendar.name)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundColor(.white)
            .padding(20)
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: isEditing ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
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

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
