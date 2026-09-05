//
//  AddEditEventBatchScreen.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI
import DSKit
import AppNavigation
import CorePersistence

public struct AddEditEventBatchScreen: View {
    @State private var viewModel: AddEditEventBatchViewModel
    @State private var didLoad = false

    public var calendarId: Int64

    private let source: BatchEditorSource
    private let resolveBatch: (Int64) -> EventBatchDataSource?
    private let onCommitBatch: (EventBatchDataSource?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(RootNavigation.self) private var navigation

    public init(
        eventsSelectionManager: PCEventsSelectionManager,
        calendarId: Int64,
        source: BatchEditorSource,
        resolveBatch: @escaping (Int64) -> EventBatchDataSource?,
        onCommit: @escaping (EventBatchDataSource?) -> Void
    ) {
        _viewModel = State(initialValue: AddEditEventBatchViewModel(eventsSelectionManager: eventsSelectionManager))
        self.calendarId = calendarId
        self.source = source
        self.resolveBatch = resolveBatch
        self.onCommitBatch = onCommit
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
        .onAppear {
            load()
        }
        .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
            if let selectedDay = newValue.first {
                viewModel.toggleEvent(on: selectedDay)
            }
        }
    }

    private func load() {
        // Load the session once. Re-appearing (e.g. returning from the event
        // editor) must not reset the in-flight edits.
        guard !didLoad else { return }
        didLoad = true
        switch source {
        case .newDay(let day):
            viewModel.load(nil, selectedDay: day)
        case .existingBatch(let id):
            guard let batch = resolveBatch(id) else { return }
            viewModel.load(batch)
        }
    }

    private func save() {
        if viewModel.save() {
            let batchDeleted = viewModel.eventBatch?.events.isEmpty == true
            onCommitBatch(viewModel.eventBatch)
            if batchDeleted {
                // Every event was removed, so the batch no longer exists.
                // Return straight to the single calendar view.
                navigation.goTo(.calendar(calendarId, toRoot: true))
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddEditEventBatchScreen(
            eventsSelectionManager: PCEventsSelectionManager(),
            calendarId: 0,
            source: .existingBatch(1),
            resolveBatch: { _ in nil },
            onCommit: { _ in }
        )
    }
    .environment(RootNavigation())
    .environment(PCKeyboardState())
}
