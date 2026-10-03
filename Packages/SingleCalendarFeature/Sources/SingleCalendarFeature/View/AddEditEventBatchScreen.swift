//
//  AddEditEventBatchScreen.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI
import DSKit
import AppNavigation

/// The batch editor.
///
/// Takes only the calendar it belongs to. Which batch is being edited is `state.assembly`,
/// and the day it was opened from no longer has to be reconstructed from a
/// `BatchEditorSource` — the stage and the anchor day are both in the state.
public struct AddEditEventBatchScreen: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(RootNavigation.self) private var navigation
    @Environment(\.pcVibe) private var vibe

    /// The editor's only exit.
    ///
    /// Named rather than left as a bare label so the UI suite has a stable handle on it. It
    /// used to reach for the Save checkmark instead — as the way *out*, and, because nothing
    /// else on that screen was addressable, as the way to tell that the editor was open at
    /// all. Both jobs are this button's now, so one identifier serves both and there is no
    /// element in these tests whose only purpose was to prove a screen had appeared.
    public static let backButtonAccessibilityIdentifier = "batch-editor-back-button"

    public let calendarID: Int64

    public init(calendarID: Int64) {
        self.calendarID = calendarID
    }

    public var body: some View {
        let viewModel = AddEditEventBatchViewModel(store: store)

        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                BatchEditorHorizontalLayout()
            } else {
                BatchEditorVerticalLayout()
            }
        }
        .toolbar {
            // An explicit Back, because the system's is a trap here.
            //
            // The system back button pops the `NavigationStack` itself. It never reaches the
            // store, so the staged assembly survives the editor that was editing it: the
            // day the user tapped keeps its marker, and the calendar then reports an event
            // that was never written. Reported as "marked in memory, not persisted" — and
            // invisible in review, because a navigation bar doing its job is not something
            // that looks like a bug.
            //
            // Routing Back through the store is the design the reducer already models:
            // `backTapped` decides what leaving means (discard the edit, keep the
            // committed rows), records a `.pop`, and `PCEventSelectionNavigator` carries it
            // out. The system button skips all three steps.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.send(.backTapped)
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .accessibilityIdentifier(Self.backButtonAccessibilityIdentifier)
            }
            ToolbarItem(placement: .principal) {
                BatchEditorTitleContent(
                    preferredTitle: viewModel.preferredTitle,
                    compactTitle: viewModel.compactTitle
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(vibe.color(for: .backgroundMain), for: .pcNavigationBar)
        .ignoresSafeArea(edges: .bottom)
        .background(vibe.color(for: .backgroundMain))
        .pcDisableInteractivePopGesture()
        .task {
            // Entry is dispatched from the visible screen, never from `init`. A
            // `navigationDestination` builds its views speculatively for screens the user
            // has not reached, and running entry there would commit a phantom batch and
            // steal day markers onto a year model that is not on screen.
            store.send(.ensureAssemblyStarted)
            store.installDayTapHandler { day in
                store.send(.toggleDay(day))
            }
        }
        .onDisappear {
            store.clearDayTapHandler()
        }
        .onChange(of: store.state.navigationRequest) { _, request in
            guard let request else { return }
            PCEventSelectionNavigator.fulfil(
                request,
                calendarID: calendarID,
                using: navigation,
                in: store
            )
        }
    }
}

#Preview {
    NavigationStack {
        AddEditEventBatchScreen(calendarID: 1)
    }
    .environment(RootNavigation())
    .environment(PCKeyboardState())
}
