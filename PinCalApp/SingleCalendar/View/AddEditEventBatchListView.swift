//
//  AddEditEventBatchListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import SwiftUI

struct AddEditEventBatchListView: View {
    @Bindable var viewModel: AddEditEventBatchListViewModel
    
    var onClose: () -> Void = {}
    var onBatchTap: () -> Void = {}
    
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(viewModel.eventBatches, id: \.self) { eventBatch in
                        Button(
                            action: {
                                viewModel.prepareAddEditBatchViewModel(with: eventBatch)
                                onBatchTap()
                            },
                            label: {
                                HStack {
                                    Text(eventBatch.name)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        )
                        .listRowBackground(eventBatch.color)
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(.colorBackgroundMain)
                .environment(\.editMode, .constant(.active))
            }
            .toolbarBackground(Color("colorBackgroundMain"), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .title) {
                    Text(viewModel.selectedDay ?? Date(), style: .date)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .background(.colorBackgroundMain)
    }

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeBatches(at: offsets)
    }
}
