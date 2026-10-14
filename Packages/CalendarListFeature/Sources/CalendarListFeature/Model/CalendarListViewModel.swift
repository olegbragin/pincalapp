//
//  CalendarListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation
import Observation
import SwiftUI
import CoreDomain
import DSKit

public enum CalendarListMode {
    case active
    case archived
}

public enum DisplayMode: String, CaseIterable {
    case list
    case grid

    var icon: String {
        switch self {
        case .list: return "rectangle.grid.1x2"
        case .grid: return "rectangle.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }

    var toggled: DisplayMode {
        switch self {
        case .list: return .grid
        case .grid: return .list
        }
    }
}

/// The panel model the view talks to: projections out, commands in.
///
/// Deliberately thin, and it is the panel rather than the owner of the data. Everything that
/// is *screen state* lives in `CalendarListState` behind `CalendarListStore`; what stays here is
/// what a value cannot hold — the card view-model cache keyed by calendar id, the add sheet's
/// own view model — plus the bindings SwiftUI needs, which are built from the store's state
/// rather than from anything this type stores.
///
/// The same shape `SingleCalendarModel` has over `PCEventSelectionManager`, and for the same
/// reason: a view should read projections and send intents, never assign state or ask what a
/// change did.
@MainActor
@Observable
public final class CalendarListViewModel {
    /// The state owner. `@ObservationIgnored` because the panel's projections read through it,
    /// and observation follows the read — so a change to `store.state` invalidates a view
    /// reading `viewModel.calendars` without the panel re-announcing it.
    ///
    /// Internal rather than private, because the view installs its failure callbacks on it.
    /// That is the one thing the panel cannot do itself: the callbacks close over the *view's*
    /// parameters, and the panel is built once, in `.task`, long after those exist. Exposing
    /// the store rather than a `callbacks` facade keeps one name for one thing — a facade would
    /// have been a second way to spell the same object, and every reader would have had to
    /// work out whether it was the same store or a narrowed view of it.
    @ObservationIgnored let store: CalendarListStore

    /// Owns the per-calendar card view models.
    ///
    /// Outside `CalendarListState` on purpose: they are a cache keyed by identity, and putting
    /// them in state would mean `Equatable` had to answer for a set of reference types and for
    /// the `@Published`-style editing state each one carries.
    @ObservationIgnored private var cardViewModels: [Int64: PCCalendarCardViewModel] = [:]

    var addEditCalendarViewModel = AddEditCalendarViewModel()

    let mode: CalendarListMode
    let undoWindowDuration: TimeInterval

    public var isAnyCardEditing: Bool {
        cardViewModels.values.contains { $0.isEditing }
    }

    // MARK: - Init

    public init(
        mode: CalendarListMode = .active,
        managing: any CalendarManaging,
        undoWindowDuration: TimeInterval = 5
    ) {
        self.mode = mode
        self.undoWindowDuration = undoWindowDuration
        self.store = CalendarListStore(
            mode: mode,
            managing: managing,
            undoWindowDuration: undoWindowDuration
        )
        // The store owns the failure; the cards are ours, so the revert is ours to make.
        store.onRenameRejected = { [weak self] calendarID, rejectedName in
            self?.revertRenamedCard(id: calendarID, to: rejectedName)
        }
    }

    // MARK: - Projections read by the view

    var calendars: [PinCalendar] {
        store.state.calendars
    }

    var displayMode: DisplayMode {
        store.state.displayMode
    }

    /// Whether the screen is a spinner.
    ///
    /// Derived from `stage` rather than stored as a flag beside it, because the old pair —
    /// `isLoading` plus `calendars.isEmpty`, conjoined *in the view body* — could disagree with
    /// itself. The reducer decides it now.
    var isLoading: Bool {
        store.state.stage == .loading
    }

    var loadFailure: Bool {
        store.state.loadFailure
    }

    var writeFailure: PCCalendarListWriteFailure? {
        store.state.writeFailure
    }

    var pendingArchive: PinCalendar? {
        store.state.pendingArchive
    }

    var isArchiveToastPresented: Bool {
        store.state.isArchiveToastPresented
    }

    var archiveToastMessage: String {
        guard let pendingArchive else { return "" }
        return "\(pendingArchive.name) archived"
    }

    var archiveToastProgress: Double {
        store.archiveToastProgress
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - Bindings

    /// `loadFailure` as something the toast can bind to.
    ///
    /// `set` is empty because nothing here *clears* the failure — a successful load does, and
    /// it does it by transitioning, not by the toast's dismissal. A binding that could write
    /// it would let a dismissed toast look like a resolved one.
    var loadFailureBinding: Binding<Bool> {
        Binding(get: { self.store.state.loadFailure }, set: { _ in })
    }

    /// `writeFailure`'s presence as something the toast can bind to.
    ///
    /// Same one-way shape, and for a sharper reason: dismissing this toast must not clear the
    /// failure, because the write did not happen and the only thing that can clear it is a
    /// write succeeding.
    var writeFailureBinding: Binding<Bool> {
        Binding(get: { self.store.state.writeFailure != nil }, set: { _ in })
    }

    /// Whether the archive toast is up.
    ///
    /// Read-only for the same reason as the two failure bindings: a dismissed toast must not be
    /// able to make a write that *did* land look like one that is still pending. The window
    /// closes on a transition — the countdown elapsing, or Undo being tapped.
    var archiveToastPresentedBinding: Binding<Bool> {
        Binding(get: { self.store.state.isArchiveToastPresented }, set: { _ in })
    }

    // MARK: - Commands

    /// Reads the list.
    ///
    /// Awaits and rethrows so the pull-to-refresh spinner comes down when the load finishes
    /// rather than when the command returns. The failure is recorded either way — in
    /// `loadFailure` for the toast, and in `onLoadFailed` for the owner — so a caller that
    /// discards the throw loses nothing but the ability to branch on it.
    func fetch() async throws {
        try await store.fetch()
    }

    func addCalendar(with name: String) {
        store.send(.createTapped(name: name))
    }

    func addItem() {
        addEditCalendarViewModel.reset()
    }

    func toggleDisplayMode() {
        store.send(.displayModeToggled)
    }

    /// Archives the calendar, opening the undo window only if the write lands.
    ///
    /// The toast used to be presented *before* the write was attempted, which made the claim
    /// "X archived" an assertion the code had not yet earned. A failed write left the calendar
    /// sitting in the active list under a banner saying it had been archived, and the five-second
    /// Undo window counted down over a change that had not happened.
    func archiveCalendarInList(_ calendar: PinCalendar) {
        store.send(.archiveTapped(calendar))
    }

    func restoreCalendarInList(_ calendar: PinCalendar) {
        store.send(.restoreTapped(calendar))
    }

    /// The only irreversible write in the app.
    func permanentlyDeleteCalendar(_ calendar: PinCalendar) {
        store.send(.permanentlyDeleteTapped(calendar))
    }

    /// Called when the user taps the toast's undo.
    ///
    /// A failed restore is reported rather than silent. This was the worst of the failures: the
    /// user was told the calendar was archived, tapped Undo, and if the restore then threw the
    /// calendar stayed archived with the toast gone and nothing said. Both halves of the undo
    /// had appeared to work and neither had.
    func undoArchive() {
        store.send(.undoArchiveTapped)
    }

    /// Re-runs the failed write, exactly as it was attempted.
    ///
    /// Not "whatever the user last asked for": the archive undo and the rename are different
    /// operations with different payloads, and a retry that re-derived them from current state
    /// could write something other than what failed.
    func retryWriteFailure() {
        store.send(.retryWriteFailure)
    }

    // MARK: - Cards

    /// The card's view model, created once per calendar and kept.
    func cardViewModel(for calendar: PinCalendar) -> PCCalendarCardViewModel {
        if let existing = cardViewModels[calendar.id] {
            existing.name = calendar.name
            existing.numberOfColumns = calendar.numberOfColumns
            return existing
        }
        let vm = PCCalendarCardViewModel(id: calendar.id, name: calendar.name, numberOfColumns: calendar.numberOfColumns, isArchived: calendar.isArchived)
        vm.onEditCommitted = { [weak self] id, newName in
            self?.store.send(.renameCommitted(calendarID: id, newName: newName))
        }
        vm.onDelete = { [weak self] in
            guard let self else { return }
            self.archiveCalendarInList(calendar)
        }
        vm.onRestore = { [weak self] in
            guard let self else { return }
            self.restoreCalendarInList(calendar)
        }
        vm.onPermanentDelete = { [weak self] in
            guard let self else { return }
            self.permanentlyDeleteCalendar(calendar)
        }
        cardViewModels[calendar.id] = vm
        return vm
    }

    /// Undoes the optimistic rename in the card that shows it.
    private func revertRenamedCard(id: Int64, to rejectedName: String) {
        guard let original = calendars.first(where: { $0.id == id }), original.name != rejectedName else { return }
        cardViewModels[id]?.restoreName(original.name)
    }
}
