//
//  AddEditEventBatchListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import SwiftUI
import AppNavigation
import CorePersistence
import DSKit
import CoreDomain

public struct AddEditEventBatchListView: View {
    @Environment(RootNavigation.self) var navigation
    @Environment(\.pcVibe) private var vibe

    @State private var viewModel: AddEditEventBatchListViewModel

    private let calendarId: Int64
    private let selectedDay: Date?

    public init(
        eventsSelectionManager: PCEventsSelectionManager,
        daySelectionManager: PCCalendarDaySelectionManager,
        calendarId: Int64,
        selectedDay: Date?
    ) {
        _viewModel = State(initialValue: AddEditEventBatchListViewModel(
            eventsSelectionManager: eventsSelectionManager,
            daySelectionManager: daySelectionManager
        ))
        self.calendarId = calendarId
        self.selectedDay = selectedDay
    }

    public var body: some View {
        // A ScrollView + LazyVStack (rather than a List) so the cards animate
        // their collapse/expand height smoothly; List snaps its row heights and
        // would make the toggle jump.
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.eventBatches, id: \.self) { eventBatch in
                    HStack(spacing: 12) {
                        BatchEventCard(
                            eventBatch: eventBatch,
                            onOpen: {
                                navigation.goTo(AppRoute.batchEditor(.existingBatch(eventBatch.id)))
                            }
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
        .toolbar {
            ToolbarItem(placement: .pcTitle) {
                Text(viewModel.selectedDay ?? Date(), style: .date)
            }
            ToolbarItem(placement: .pcTrailing) {
                Button {
                    startNewBatch()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New batch")
                .accessibilityIdentifier("add-batch-button")
            }
        }
        .background(vibe.color(for: .backgroundMain))
        .onAppear {
            viewModel.prepare(with: viewModel.eventsSelectionManager.batches(for: selectedDay ?? Date()), and: selectedDay)
        }
        .onChange(of: viewModel.eventBatchesToDelete) { _, newValue in
            guard !newValue.isEmpty else { return }
            viewModel.deleteBatches(newValue)
            viewModel.prepare(with: viewModel.eventsSelectionManager.batches(for: selectedDay ?? Date()), and: selectedDay)
            if viewModel.eventBatches.isEmpty {
                navigation.goTo(.calendar(calendarId, toRoot: true))
            }
        }
    }

    ///// Opens the batch editor for a brand-new batch anchored on the tapped day.
    ///// It stages a placeholder event (mirroring the day-tap path from the single
    ///// calendar view) so the editor has a starting event and the day preselected.
    private func startNewBatch() {
        let day = selectedDay ?? Date()
        viewModel.eventsSelectionManager.prepare(with: [
            EventDataSource(name: "", date: day, color: PCColorOption.option1.colorName)
        ])
        navigation.goTo(.batchEditor(.newDay(day)))
    }
}

/// A single batch card in the list. It shows the batch name and the events it
/// includes (a colored dot + "Name at time" row). The card is capped at
/// `collapsedMaxHeight` when collapsed; if its content overflows that limit a
/// "Show more"/"Show less" toggle is shown so the user can expand it to full height.
private struct BatchEventCard: View {
    let eventBatch: EventBatchDataSource
    let onOpen: () -> Void

    @Environment(\.pcVibe) private var vibe

    @State private var naturalHeight: CGFloat = 0
    @State private var isExpanded = false

    private let collapsedMaxHeight: CGFloat = 150

    private var showsToggle: Bool { naturalHeight > collapsedMaxHeight }

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
        ForEach(eventBatch.events, id: \.self) { event in
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
        let colorNameToUse = eventBatch.colorName.isEmpty ? eventBatch.events.first?.color : eventBatch.colorName
        guard let colorNameToUse, !colorNameToUse.isEmpty else { return .clear }
        return vibe.eventColor(named: colorNameToUse)
    }

    private func eventColor(_ event: EventDataSource) -> Color {
        vibe.eventColor(named: event.color)
    }
}

private struct BatchCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    let day = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    let manager = PCEventsSelectionManager()
    manager.batches = [
        EventBatchDataSource(
            id: 1,
            name: "Morning routine",
            colorName: "eventColorOption1",
            events: (0..<8).map { index in
                EventDataSource(
                    id: Int64(index + 1),
                    name: "Task \(index + 1)",
                    date: day.addingTimeInterval(TimeInterval(index) * 3600),
                    color: "eventColorOption1"
                )
            },
            date: day
        ),
        EventBatchDataSource(
            id: 2,
            name: "Evening",
            colorName: "eventColorOption2",
            events: [
                EventDataSource(name: "Dinner", date: day.addingTimeInterval(19 * 3600), color: "eventColorOption2"),
                EventDataSource(name: "Movie", date: day.addingTimeInterval(21 * 3600), color: "eventColorOption2"),
            ],
            date: day
        ),
    ]
    return NavigationStack {
        AddEditEventBatchListView(
            eventsSelectionManager: manager,
            daySelectionManager: manager.daySelectionManager,
            calendarId: 1,
            selectedDay: day
        )
    }
    .environment(RootNavigation())
}
