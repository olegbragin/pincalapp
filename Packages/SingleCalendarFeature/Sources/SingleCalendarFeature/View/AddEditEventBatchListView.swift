//
//  AddEditEventBatchListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import SwiftUI
import AppNavigation
import CoreDomain
import DSKit

/// The batches on one day.
///
/// Takes no parameters: which day is `state.day`, and the batches on it are
/// `state.dayBatches`. It used to be handed both, plus a stored copy of the answer.
public struct AddEditEventBatchListView: View {
    @Environment(RootNavigation.self) var navigation
    @Environment(\.pcVibe) private var vibe
    @Environment(PCEventSelectionManager.self) private var store

    /// Held, not built per render.
    ///
    /// This is the one view model that stores anything: `pendingDeletion` is view-scoped
    /// state, and a fresh instance per `body` evaluation throws it away. Building it
    /// inline looks harmless because the other three view models are structs holding no
    /// state — but here the delete would set `pendingDeletion` on an object SwiftUI then
    /// discards, `onChange` would never fire, and the batch would silently survive.
    @State private var viewModel: AddEditEventBatchListViewModel?

    private let calendarID: Int64

    public init(calendarID: Int64) {
        self.calendarID = calendarID
    }

    public var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            // The store comes from the environment, so it is not available in `init`.
            if viewModel == nil {
                viewModel = AddEditEventBatchListViewModel(store: store)
            }
        }
    }

    /// A ScrollView + LazyVStack (rather than a List) so the cards animate
    /// their collapse/expand height smoothly; List snaps its row heights and
    /// would make the toggle jump.
    private func content(_ viewModel: AddEditEventBatchListViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.eventBatches) { eventBatch in
                    HStack(spacing: 12) {
                        BatchEventCard(
                            eventBatch: eventBatch,
                            onOpen: { viewModel.open(eventBatch) }
                        )

                        Button {
                            viewModel.remove(eventBatch)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete batch")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(vibe.color(for: .backgroundMain))
        .toolbarBackground(vibe.color(for: .backgroundMain), for: .pcNavigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .pcLeading) {
                Button {
                    store.send(.backTapped)
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
            ToolbarItem(placement: .pcTitle) {
                Text(viewModel.selectedDay ?? Date(), style: .date)
            }
            ToolbarItem(placement: .pcTrailing) {
                Button {
                    viewModel.startNewBatch(on: viewModel.selectedDay ?? Date())
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New batch")
                .accessibilityIdentifier("add-batch-button")
            }
        }
        .background(vibe.color(for: .backgroundMain))
        .onChange(of: viewModel.pendingDeletion) { _, staged in
            guard !staged.isEmpty else { return }
            viewModel.confirmDelete()
            // No re-priming: `eventBatches` is computed from the store, so a deletion is
            // already reflected in the next render.
            if viewModel.eventBatches.isEmpty {
                navigation.goTo(.calendar(calendarID, toRoot: true))
            }
        }
    }
}

/// A single batch card in the list. It shows the batch name and the events it
/// includes (a colored dot + "Name at time" row). The card is capped at
/// `collapsedMaxHeight` when collapsed; if its content overflows that limit a
/// "Show more"/"Show less" toggle is shown so the user can expand it to full height.
private struct BatchEventCard: View {
    let eventBatch: CalendarEventBatch
    let onOpen: () -> Void

    @Environment(\.pcVibe) private var vibe

    @State private var naturalHeight: CGFloat = 0
    @State private var isExpanded = false

    private let collapsedMaxHeight: CGFloat = 150

    private var showsToggle: Bool {
        naturalHeight > collapsedMaxHeight
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                eventRows
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: isExpanded ? nil : collapsedMaxHeight, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(batchColor)
            )
            // The toggle sits at the bottom of the card, full width, with a
            // gradient (card color at the bottom -> transparent upward) so it
            // looks like it slightly covers the content behind it.
            .overlay(alignment: .bottom) {
                if showsToggle {
                    toggleButton
                }
            }
            // Clip everything (including the toggle) to the card's rounded shape
            // so the toggle fully corresponds with the card bounds.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Measures the natural (un-capped) height of the padded content so we
            // know whether it overflows the collapsed limit.
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    eventRows
                }
                .padding()
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BatchCardHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(BatchCardHeightKey.self) { naturalHeight = $0 }
            .animation(.easeInOut(duration: 0.25), value: isExpanded)
        }
    }

    private var header: some View {
        HStack {
            Text(eventBatch.name)
                .font(.headline)
                .foregroundStyle(vibe.color(for: .foregroundOnEventCard))
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(vibe.color(for: .foregroundOnEventCard))
        }
        .padding(.bottom, 6)
    }

    private var eventRows: some View {
        ForEach(eventBatch.events) { event in
            HStack(spacing: 8) {
                Circle()
                    .fill(eventColor(event))
                    .frame(width: 10, height: 10)
                Text(.eventAt(event.name, event.date.formatted(date: .omitted, time: .shortened)))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(vibe.color(for: .foregroundOnEventCard))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            Text(isExpanded ? .show_less : .show_more)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(vibe.color(for: .foregroundOnEventCard))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        // Gradient: batch card color at the bottom fading to transparent at the
        // top, so the toggle slightly covers the content behind it.
        .background(
            LinearGradient(
                colors: [batchColor, batchColor.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
        .contentShape(Rectangle())
    }

    private var batchColor: Color {
        let colorNameToUse = eventBatch.colorName.isEmpty ? eventBatch.events.first?.colorName : eventBatch.colorName
        guard let colorNameToUse, !colorNameToUse.isEmpty else { return .clear }
        return vibe.eventColor(named: colorNameToUse)
    }

    private func eventColor(_ event: CalendarEvent) -> Color {
        vibe.eventColor(named: event.colorName)
    }
}

private struct BatchCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    NavigationStack {
        AddEditEventBatchListView(calendarID: 1)
    }
    .environment(RootNavigation())
}
