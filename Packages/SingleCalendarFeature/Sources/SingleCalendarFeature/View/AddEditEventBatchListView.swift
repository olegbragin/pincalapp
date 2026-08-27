//
//  AddEditEventBatchListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import SwiftUI
import AppNavigation
import DSKit

public struct AddEditEventBatchListView: View {
    @Bindable public var viewModel: AddEditEventBatchListViewModel

    public init(viewModel: AddEditEventBatchListViewModel) {
        self.viewModel = viewModel
    }
    @Environment(RootNavigation.self) var navigation

    public var body: some View {
        List {
            ForEach(viewModel.eventBatches, id: \.self) { eventBatch in
                PCCard {
                    Button(
                        action: {
                            viewModel.prepareAddEditBatchViewModel(with: eventBatch)
                            navigation.push(.batchEditor(.existingBatch(eventBatch)))
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
        .background(Color.init("colorBackgroundMain"))
        .environment(\.editMode, .constant(.active))
        .toolbarBackground(Color("colorBackgroundMain", bundle: .main), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .title) {
                Text(viewModel.selectedDay ?? Date(), style: .date)
            }
        }
        .background(Color.init("colorBackgroundMain"))
    }

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeBatches(at: offsets)
    }
}
