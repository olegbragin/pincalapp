//
//  AddEditEventBatchListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import SwiftUI

struct AddEditEventBatchListView: View {
    @Bindable var viewModel: AddEditEventBatchListViewModel
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(viewModel.eventBatches, id: \.self) { eventBatch in
                        Button(
                            action: {
                                viewModel.prepareAddEditBatchViewModel(with: eventBatch)
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
                .environment(\.editMode, editMode)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isEditing)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    USEditButton(isEditing: $viewModel.isEditing) { isEditing in
                        if isEditing {
                            viewModel.commitDelete()
                        } else {
                            viewModel.isEditing.toggle()
                        }
                    }
                }
                ToolbarItem(placement: .title) {
                    Text(viewModel.selectedDay ?? Date(), style: .date)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    USEditButton(
                        isEditing: $viewModel.isEditing,
                        action: { isEditing in
                            if isEditing {
                                viewModel.cancel()
                            } else {
                                viewModel.prepareAddEditBatchViewModel(with: nil)
                            }
                        },
                        activeContent: {
                            AnyView(Text("Cancel"))
                        },
                        inactiveContent: {
                            AnyView(Image(systemName: "plus"))
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $viewModel.addEditEventBatchModel.isPresented) {
                AddEditEventBatchView(viewModel: viewModel.addEditEventBatchModel)
            }
        }
        .onChange(of: viewModel.addEditEventBatchModel.isPresented) {
            if $0 != $1, !$1 {
                viewModel.addEditEventBatchModel.reset()
                viewModel.cancel()
            }
        }
        .onChange(of: viewModel.addEditEventBatchModel.eventBatch) {
            if $0 != $1, let eventBatchToCommit = $1 {
                viewModel.apply(with: eventBatchToCommit)
            }
        }
        .onChange(of: viewModel.isEditing) {
            if $0 != $1 {
                editMode?.wrappedValue = $1 ? .active : .inactive
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeBatches(at: offsets)
    }
}
