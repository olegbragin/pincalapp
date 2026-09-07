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
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .toolbarBackground(Color.dsKit.colorBackgroundMain, for: .pcNavigationBar)
        .toolbar {
            ToolbarItem(placement: .pcTitle) {
                Text(viewModel.selectedDay ?? Date(), style: .date)
            }
        }
        .background(Color.dsKit.colorBackgroundMain)
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

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeBatches(at: offsets)
    }
}
