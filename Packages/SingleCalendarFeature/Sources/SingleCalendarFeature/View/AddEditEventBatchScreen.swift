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

    public var calendarId: Int64
    private let source: BatchEditorSource

    @Environment(\.dismiss) private var dismiss
    @Environment(RootNavigation.self) private var navigation

    public init(
        eventsSelectionManager: PCEventsSelectionManager,
        calendarId: Int64,
        source: BatchEditorSource,
        eventBatch: EventBatchDataSource?
    ) {
        let selectedDay: Date?
        if case .newDay(let day) = source {
            selectedDay = day
        } else {
            selectedDay = nil
        }
        _viewModel = State(initialValue: AddEditEventBatchViewModel(
            eventsSelectionManager: eventsSelectionManager,
            calendarId: calendarId,
            eventBatch: eventBatch,
            selectedDay: selectedDay
        ))
        self.calendarId = calendarId
        self.source = source
    }

    public var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                BatchEditorHorizontalLayout(viewModel: viewModel)
            } else {
                BatchEditorVerticalLayout(viewModel: viewModel)
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
        .task {
            viewModel.setup()
        }
        .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
            if let selectedDay = newValue.first {
                viewModel.toggleEvent(on: selectedDay)
            }
        }
        .onChange(of: viewModel.didSave) { _, didSave in
            guard didSave else { return }
            let batchDeleted = viewModel.eventBatch?.events.isEmpty == true
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
            eventBatch: nil
        )
    }
    .environment(RootNavigation())
    .environment(PCKeyboardState())
}
