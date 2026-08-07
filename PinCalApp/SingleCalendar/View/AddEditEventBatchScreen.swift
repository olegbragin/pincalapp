//
//  AddEditEventBatchScreen.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI

struct AddEditEventBatchScreen: View {
    @Bindable var viewModel: AddEditEventBatchViewModel
    
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    
    var body: some View {
        AddEditEventBatchView(
            viewModel: viewModel,
            onSave: onSave
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                titleContent
            }
        }
        .toolbarBackground(Color("colorBackgroundMain"), for: .navigationBar)
    }
    
    private var titleContent: some View {
        ViewThatFits(in: .horizontal) {
            preferredTitle
            compactTitle
        }
    }
    
    @ViewBuilder
    private var preferredTitle: some View {
        let days = viewModel.selectedDays.sorted()
        if let start = days.first {
            if days.count > 1, let end = days.last {
                Text("\(start.formatted(.dateTime.day().month(.abbreviated))) - \(end.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Text(start.formatted(date: .long, time: .omitted))
                    .font(.headline)
                    .lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    private var compactTitle: some View {
        let days = viewModel.selectedDays.sorted()
        if let start = days.first {
            if days.count > 1, let end = days.last {
                Text("\(start.formatted(date: .numeric, time: .omitted))\n\(end.formatted(date: .numeric, time: .omitted))")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text(start.formatted(date: .numeric, time: .omitted))
                    .font(.headline)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddEditEventBatchScreen(
            viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")])
        )
    }
}
