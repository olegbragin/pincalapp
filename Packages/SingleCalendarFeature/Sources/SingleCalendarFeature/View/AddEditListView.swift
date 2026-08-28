//
//  AddEditListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI
import DSKit

public struct AddEditListView: View {
    @Bindable public var viewModel: AddEditListViewModel

    public init(viewModel: AddEditListViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        List {
            ForEach(viewModel.events, id: \.self) { event in
                PCCard {
                    Button(
                        action: {
                            viewModel.prepareAddEditViewModel(with: event)
                        },
                        label: {
                            HStack(spacing: 12) {
                                Text(.eventAt(event.name, event.date.formatted(date: .omitted, time: .shortened)))
                                
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(minWidth: 0, maxWidth: .infinity)
                        }
                    )
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(event.color))
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(item: $viewModel.editingEvent) { _ in
            var view = AddEditEventView(viewModel: viewModel.addEditEventModel)
            view.onCommit = { event in
                viewModel.apply(with: event)
                viewModel.editingEvent = nil
                viewModel.addEditEventModel.reset()
            }
            return view
        }
        .onChange(of: viewModel.editingEvent) { _, newValue in
            if newValue == nil {
                // Handles swipe-back/cancel without Save, or as fallback
                // if onCommit wasn't invoked. commitPendingEventIfNeeded is safe
                // to call multiple times (it clears after first apply).
                if viewModel.addEditEventModel.event != nil {
                    viewModel.commitPendingEventIfNeeded()
                } else {
                    viewModel.addEditEventModel.reset()
                }
            }
        }
    }
}

#Preview {
    AddEditListView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
