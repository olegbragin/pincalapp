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

public struct AddEditEventBatchListView: View {
    @Environment(RootNavigation.self) var navigation

    @State private var viewModel: AddEditEventBatchListViewModel

    private let calendarId: Int64
    private let loadBatches: () -> [EventBatchDataSource]
    private let selectedDay: Date?
    var onDeleteBatches: (([EventBatchDataSource]) -> Void)?

    public init(
        eventsSelectionManager: PCEventsSelectionManager,
        daySelectionManager: PCCalendarDaySelectionManager,
        calendarId: Int64,
        loadBatches: @escaping () -> [EventBatchDataSource],
        selectedDay: Date?,
        onDeleteBatches: (([EventBatchDataSource]) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: AddEditEventBatchListViewModel(
            eventsSelectionManager: eventsSelectionManager,
            daySelectionManager: daySelectionManager
        ))
        self.calendarId = calendarId
        self.loadBatches = loadBatches
        self.selectedDay = selectedDay
        self.onDeleteBatches = onDeleteBatches
    }

    public var body: some View {
        List {
            ForEach(viewModel.eventBatches, id: \.self) { eventBatch in
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
                                    ForEach(eventBatch.eventsForDay(viewModel.selectedDay), id: \.self) { event in
                                        Text("at \(event.date.formatted(date: .omitted, time: .shortened))")
                                    }
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
                            .fill(eventBatch.color)
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.dsKit.colorBackgroundMain)
        .environment(\.editMode, .constant(.active))
        .toolbarBackground(Color.dsKit.colorBackgroundMain, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .title) {
                Text(viewModel.selectedDay ?? Date(), style: .date)
            }
        }
        .background(Color.dsKit.colorBackgroundMain)
        .onAppear {
            viewModel.prepare(with: loadBatches(), and: selectedDay)
        }
        .onChange(of: viewModel.eventBatchesToDelete) { _, newValue in
            guard !newValue.isEmpty else { return }
            onDeleteBatches?(newValue)
            viewModel.prepare(with: loadBatches(), and: selectedDay)
            if viewModel.eventBatches.isEmpty {
                navigation.goTo(.calendar(calendarId, toRoot: true))
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeBatches(at: offsets)
    }
}
