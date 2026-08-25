//
//  AddEditEventBatchListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import SwiftUI

struct AddEditEventBatchListView: View {
    @Bindable var viewModel: AddEditEventBatchListViewModel
    @Environment(RootNavigation.self) var navigation

    var body: some View {
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
                                Text(eventBatch.name)
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
        .background(.colorBackgroundMain)
        .environment(\.editMode, .constant(.active))
        .toolbarBackground(Color("colorBackgroundMain"), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .title) {
                Text(viewModel.selectedDay ?? Date(), style: .date)
            }
        }
        .background(.colorBackgroundMain)
    }

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeBatches(at: offsets)
    }
}
