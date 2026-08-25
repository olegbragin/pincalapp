//
//  AddEditListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI

struct AddEditListView: View {
    @Bindable var viewModel: AddEditListViewModel
    
    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(item: $viewModel.editingEvent) { _ in
            AddEditEventView(viewModel: viewModel.addEditEventModel)
        }
        .onChange(of: viewModel.addEditEventModel.event) {
            if $0 != $1, let eventToCommit = $1 {
                viewModel.apply(with: eventToCommit)
            }
        }
        .onChange(of: viewModel.editingEvent) { _, newValue in
            if newValue == nil {
                viewModel.addEditEventModel.reset()
            }
        }
    }
}

#Preview {
    AddEditListView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
