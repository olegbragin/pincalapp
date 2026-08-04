//
//  EventListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI

struct EventListView: View {
    @Bindable var viewModel: EventListViewModel
    
    var body: some View {
        VStack {
            List {
                ForEach(viewModel.events, id: \.self) { event in
                    Button(
                        action: {
                            viewModel.prepareAddEditViewModel(with: event)
                        },
                        label: {
                            HStack {
                                Text(.eventAt(event.name, event.date.formatted(date: .omitted, time: .shortened)))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(minWidth: 0, maxWidth: .infinity)
                        }
                    )
                    .listRowBackground(Color(event.color))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationDestination(isPresented: $viewModel.addEditEventModel.isPresented) {
            AddEditEventView(viewModel: viewModel.addEditEventModel)
        }
        .onChange(of: viewModel.addEditEventModel.event) {
            if $0 != $1, let eventToCommit = $1 {
                viewModel.apply(with: eventToCommit)
            }
        }
        .onChange(of: viewModel.addEditEventModel.isPresented) {
            if $0 != $1, !$1 {
                viewModel.addEditEventModel.reset()
            }
        }
    }
}

#Preview {
    EventListView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
