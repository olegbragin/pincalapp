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
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                BatchEditorHorizontalLayout(viewModel: viewModel, onSave: onSave)
            } else {
                BatchEditorVerticalLayout(viewModel: viewModel, onSave: onSave)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                DSButton {
                    onCancel()
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                BatchEditorTitleContent(
                    preferredTitle: viewModel.preferredTitle,
                    compactTitle: viewModel.compactTitle
                )
            }
        }
        .toolbarBackground(Color("colorBackgroundMain"), for: .navigationBar)
        .ignoresSafeArea(edges: .bottom)
        .background(.colorBackgroundMain)
        .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
            if let selectedDay = newValue.first {
                viewModel.toggleEvent(on: selectedDay)
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
