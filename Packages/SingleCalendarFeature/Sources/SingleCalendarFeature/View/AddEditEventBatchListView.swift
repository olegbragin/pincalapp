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
        List {
            ForEach(viewModel.eventBatches, id: \.self) { eventBatch in
                HStack(spacing: 12) {
                    PCCard {
                        Button(
                            action: {
                                navigation.goTo(AppRoute.batchEditor(.existingBatch(eventBatch.id)))
                            },
                            label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(eventBatch.name)
                                            .font(.headline)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        )
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(batchColor(eventBatch))
                        )
                    }

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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

    private func batchColor(_ eventBatch: EventBatchDataSource) -> Color {
        let colorNameToUse = eventBatch.colorName.isEmpty ? eventBatch.events.first?.color : eventBatch.colorName
        guard let colorNameToUse, !colorNameToUse.isEmpty else { return .clear }
        return vibe.eventColor(named: colorNameToUse)
    }

    /// Opens the batch editor for a brand-new batch anchored on the tapped day.
    /// It stages a placeholder event (mirroring the day-tap path from the single
    /// calendar view) so the editor has a starting event and the day preselected.
    private func startNewBatch() {
        let day = selectedDay ?? Date()
        viewModel.eventsSelectionManager.prepare(with: [
            EventDataSource(name: "", date: day, color: PCColorOption.option1.colorName)
        ])
        navigation.goTo(.batchEditor(.newDay(day)))
    }
}
