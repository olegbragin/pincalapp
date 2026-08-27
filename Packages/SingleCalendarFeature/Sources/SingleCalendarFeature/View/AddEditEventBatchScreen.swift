//
//  AddEditEventBatchScreen.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI
import DSKit

public struct AddEditEventBatchScreen: View {
    @Bindable public var viewModel: AddEditEventBatchViewModel

    public var onCommit: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AddEditEventBatchViewModel, onCommit: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onCommit = onCommit
    }

    public var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                BatchEditorHorizontalLayout(viewModel: viewModel, onSave: save)
            } else {
                BatchEditorVerticalLayout(viewModel: viewModel, onSave: save)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                BatchEditorTitleContent(
                    preferredTitle: viewModel.preferredTitle,
                    compactTitle: viewModel.compactTitle
                )
            }
        }
        .toolbarBackground(Color("colorBackgroundMain", bundle: .main), for: .navigationBar)
        .ignoresSafeArea(edges: .bottom)
        .background(Color("colorBackgroundMain", bundle: .main))
        .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
            if let selectedDay = newValue.first {
                viewModel.toggleEvent(on: selectedDay)
            }
        }
    }

    private func save() {
        if viewModel.save() {
            onCommit?()
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AddEditEventBatchScreen(
            viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")])
        )
    }
    .environment(PCKeyboardState())
}
