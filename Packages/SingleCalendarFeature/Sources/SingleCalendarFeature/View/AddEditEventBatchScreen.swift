//
//  AddEditEventBatchScreen.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI
import AppNavigation
import DSKit

/// The batch editor.
///
/// Takes only the calendar it belongs to. Which batch is being edited is `state.assembly`,
/// and the day it was opened from no longer has to be reconstructed from a
/// `BatchEditorSource` — the stage and the anchor day are both in the state.
///
/// ## Presented as a sheet
///
/// It used to be pushed onto the calendar's `NavigationStack`, which meant the calendar it
/// was editing was not there any more — on iPad a push replaces the detail column in place,
/// so "edit this batch over this calendar" was not expressible. As a sheet the calendar stays
/// mounted underneath and its day markers track every edit live, because `dayEventColors` is
/// re-derived at every reducer exit and projected into the main year model.
///
/// That is also why this view must keep doing its own day-tap bookkeeping. The main calendar
/// installed its tap handler in its own `.task` and never removed it — a sheet does not
/// replace what is beneath it — so the editor takes the single handler slot on appearing and
/// clears it on disappearing, and `SingleCalendarView` re-installs its own when the sheet
/// closes. One slot, two owners, handed over explicitly; the alternative is a calendar that
/// stops responding to taps the moment an editor has been opened once.
public struct AddEditEventBatchScreen: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(RootNavigation.self) private var navigation
    @Environment(\.pcVibe) private var vibe

    /// The editor's only exit.
    ///
    /// A **Close**, not a Back, because this screen is the root of a sheet and there is nothing
    /// behind it to go back to — a chevron on a sheet that covers the window promises a screen
    /// that does not exist.
    ///
    /// Named rather than left as a bare label so the UI suite has a stable handle on it. It
    /// used to reach for the Save checkmark instead — as the way *out*, and, because nothing
    /// else on that screen was addressable, as the way to tell that the editor was open at
    /// all. Both jobs are this button's now, so one identifier serves both and there is no
    /// element in these tests whose only purpose was to prove a screen had appeared.
    ///
    /// The identifier still says "back". Renaming it would touch ~28 call sites for no gain,
    /// and it describes the *role* — the editor's exit — which has not changed.
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
            // An explicit Close, because there is no implicit one here.
            //
            // A sheet has no stack to pop, so there is no system back button: without this
            // the editor would be a screen with no visible way out at all. It dispatches
            // rather than calling `dismiss()` because `backTapped` is what decides what
            // leaving means — discard nothing, merge whatever is staged, delete the row if
            // the batch was emptied — and that decision predates the sheet. A dismiss that
            // bypassed the store skipped all of it, which is the one bug this button was
            // introduced for: a system back that left a staged assembly behind, so the tapped
            // day kept a marker for an event that was never written.
            //
            // It is an `xmark` rather than a `chevron.backward` for the same reason it is
            // named Close: this is the root of the sheet, so there is no previous screen for
            // a chevron to point at.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.send(.backTapped)
                } label: {
                    Label(.close, systemImage: "xmark")
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
        // A sheet has no stack to push, so there is no interactive pop to disable and no
        // system back to hide. Both stay applied to the calendar beneath, which does have a
        // stack and does need them.
        .toolbarBackground(vibe.color(for: .backgroundMain), for: .pcNavigationBar)
        .ignoresSafeArea(edges: .bottom)
        .background(vibe.color(for: .backgroundMain))
        .task {
            // This sheet's store is the one injected at the app root, and the app root
            // injects `session.currentEventSelection` — the store for the calendar currently
            // open. Nothing else could plausibly be wrong with *which* store this is: there
            // is exactly one, injected above everything. What *can* be wrong is that it is
            // the store for a different calendar than the one this editor was opened from —
            // a sheet outlives a calendar switch in a way a push did not, because a
            // navigation stack would have been torn down with the column it belonged to.
            //
            // The symptom of that is silent and expensive: `.ensureAssemblyStarted` and every
            // subsequent edit would be written to another calendar's rows by a destructive
            // `saveCalendar`. So it is checked here, once, where entry is dispatched, and it
            // traps rather than continuing. `calendarID` is `0` until the store's first sync
            // lands, which is not a mismatch worth stopping for — the assertion is about a
            // store that has settled on a *different* calendar.
            #if DEBUG
                assert(
                    store.state.calendarID == 0 || store.state.calendarID == calendarID,
                    """
                    The batch editor's sheet is showing calendar \(calendarID) but the injected \
                    store belongs to calendar \(store.state.calendarID). Editing here would write \
                    to the wrong calendar's rows.
                    """
                )
            #endif
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
    .environment(PreviewEventSelectionStore.make())
    .environment(PCKeyboardState())
}
