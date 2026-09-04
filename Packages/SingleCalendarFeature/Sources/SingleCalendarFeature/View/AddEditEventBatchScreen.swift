//
//  AddEditEventBatchScreen.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI
import DSKit
import AppNavigation

public struct AddEditEventBatchScreen: View {
    @Bindable public var viewModel: AddEditEventBatchViewModel

    public var onCommit: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(RootNavigation.self) private var navigation

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
        .toolbarBackground(Color.dsKit.colorBackgroundMain, for: .navigationBar)
        .ignoresSafeArea(edges: .bottom)
        .background(Color.dsKit.colorBackgroundMain)
        .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
            if let selectedDay = newValue.first {
                viewModel.toggleEvent(on: selectedDay)
            }
        }
    }

    private func save() {
        if viewModel.save() {
            let batchDeleted = viewModel.eventBatch?.events.isEmpty == true
            onCommit?()
            if batchDeleted {
                // Every event was removed, so the batch no longer exists.
                // Return straight to the single calendar view.
                navigation.popToRoot()
            } else {
                dismiss()
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
    .environment(RootNavigation())
    .environment(PCKeyboardState())
}
