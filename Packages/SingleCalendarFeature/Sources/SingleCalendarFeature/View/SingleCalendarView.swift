//
//  SingleCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import SwiftUI
import AppNavigation
import DSKit

public struct SingleCalendarView: View {
    @Bindable public var viewModel: SingleCalendarModel

    public init(viewModel: SingleCalendarModel) {
        self.viewModel = viewModel
    }

    @Environment(RootNavigation.self) var navigation
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(\.pcVibe) private var vibe

    /// Local so dismissing the toast does not touch the store: the failure is the store's
    /// to hold until it is retried, and clearing it here would unblock the calendar switch
    /// for a save that still has not landed. The store clears `failedSave` itself when a
    /// write succeeds, and this follows it down.
    @State private var isSaveFailedToastPresented = false

    public var body: some View {
        ZStack {
            SingleCalendarStateView(state: viewModel.state) {
                AnyView(
                    VStack(spacing: 0) {
                        // `isAtRoot` mirrors the toolbar's own guard below. The picker is
                        // the main calendar's own multi-select session now, and the batch
                        // editor no longer shares this panel's selection state, so nothing
                        // behind a pushed screen can flip it.
                        if navigation.isAtRoot, viewModel.isMultiSelectMode {
                            PCExpandedColorPicker(selectedColor: viewModel.multiSelectColorBinding)
                                .disabled(viewModel.isColorPickerDisabled)
                        }
                        PCCalendarYearView(
                            viewModel: viewModel.yearModel,
                            onLongPress: { viewModel.setMultiSelectMode(true) },
                            onYearSelect: { viewModel.switchYear(to: $0) }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: viewModel.yearModel.numberOfColumns) { old, new in
                        if old != new {
                            viewModel.setNumberOfColumns(new)
                        }
                    }
                )
            }
            .padding(6)
            .pcDisableInteractivePopGesture()
            .navigationTitle(viewModel.label)
            .pcNavigationBarTitleDisplayMode(.inline)
            .toolbarBackground(vibe.color(for: .backgroundMain), for: .pcNavigationBar)
            .toolbar { toolbarContent }
            .id(viewModel.calendarid)
            .navigationDestination(for: AppRoute.self) { route in
                // No payload: each screen reads what it needs from the store, so there is
                // no per-destination `case .batchEditor(let source)` preamble here to keep
                // in step with the reducer.
                switch route {
                case .dayBatches:
                    AddEditEventBatchListView(calendarID: viewModel.calendarid)
                case .batchEditor:
                    AddEditEventBatchScreen(calendarID: viewModel.calendarid)
                case .eventEditor:
                    AddEditEventView()
                case .calendar:
                    EmptyView()
                case .addCalendar:
                    EmptyView()
                case .sidebar:
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sensoryFeedback(.success, trigger: viewModel.isMultiSelectMode)
        .task(id: viewModel.calendarid) {
            viewModel.installDayTapHandler()
            await viewModel.fetch()
        }
        .onDisappear {
            viewModel.clearDayTapHandler()
            // Leaving the calendar detail (back to the list, or switching calendars) must
            // exit any active multi-select session so a later reopen starts fresh. Guarded
            // on `isAtRoot` because `onDisappear` also fires when a destination is pushed
            // on top, and a batch edit in progress must not be reset.
            if navigation.isAtRoot {
                viewModel.cancelMultiSelect()
            }
        }
        .onChange(of: navigation.isAtRoot) { _, isAtRoot in
            if isAtRoot {
                viewModel.cancelMultiSelect()
            }
        }
        .onChange(of: store.state.dayEventColors) { _, _ in
            // The editor screens dispatch to the store directly, so the main panel's
            // markers have to follow the store rather than wait to be told. Projecting
            // only on `fetch` was not enough: a staged edit writes nothing, so no cache
            // change fires, and removing the last event of a day left its marker behind.
            viewModel.projectMarkers()
        }
        .onChange(of: store.state.navigationRequest) { _, request in
            // This is where the main calendar leaves the line. The reducer decides that a
            // day tap means "open the batch editor" and says so in `navigationRequest`;
            // carrying that out is the view layer's job, and this is the only place on
            // this screen that can. Without it a day tap staged a batch and nothing
            // happened — which is exactly what the UI suite caught.
            guard let request else { return }
            PCEventSelectionNavigator.fulfil(
                request,
                calendarID: viewModel.calendarid,
                using: navigation,
                in: store
            )
        }
        .onChange(of: store.failedSave) { _, failure in
            // Raised by the store when a write did not land. The toast is the only way the
            // user learns their work is not saved, and Retry is the only way out — which is
            // why there is no timeout here: a failed save must not fade away unattended,
            // unlike the transient toasts that need no answer.
            isSaveFailedToastPresented = failure != nil
        }
        .pcToast(
            isPresented: $isSaveFailedToastPresented,
            position: .bottom,
            message: saveFailureMessage,
            actionTitle: "Retry",
            action: { store.retryFailedSave() },
            backgroundColor: .black.opacity(0.85),
            progress: 1,
            identifier: "save-failed-toast",
            actionIdentifier: "save-failed-toast-button"
        )
    }

    /// User-facing text for a failed save.
    ///
    /// The store's `message` is the raw thrown error, which is not something to put in front
    /// of someone — ObjectBox surfaces internal failures there. So the specifics stay in the
    /// store for diagnosis and the user gets the actionable half: the work is not saved, and
    /// Retry is right there on the toast.
    private var saveFailureMessage: String {
        store.failedSave == nil ? "" : "Couldn't save changes. Retry to keep them."
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if navigation.isAtRoot, !viewModel.isArchived {
            ToolbarItem {
                Button(
                    viewModel.isMultiSelectMode ? "Save" : "Multiselect",
                    systemImage: viewModel.isMultiSelectMode ? "checkmark" : "plus.rectangle.on.rectangle"
                ) {
                    if viewModel.isMultiSelectMode {
                        viewModel.confirmMultiSelect()
                    } else {
                        viewModel.setMultiSelectMode(true)
                    }
                }
            }
        }
    }
}

#Preview {
    SingleCalendarViewPreview()
}

private struct SingleCalendarViewPreview: View {
    var body: some View {
        Text("SingleCalendarView Preview")
    }
}
