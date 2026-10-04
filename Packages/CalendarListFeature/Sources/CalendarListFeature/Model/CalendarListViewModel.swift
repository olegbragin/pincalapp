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

@MainActor
@Observable
public final class CalendarListViewModel {
    private let managing: any CalendarManaging
    let mode: CalendarListMode

    var calendars: [PinCalendar] = []
    var displayMode: DisplayMode = .list

    var addEditCalendarViewModel = AddEditCalendarViewModel()
    var isLoading = true

    /// Calendar awaiting the archive timeout; nil when no toast is pending.
    var pendingArchive: PinCalendar?
    var isArchiveToastPresented = false
    var archiveToastMessage = ""
    var archiveToastProgress: Double {
        archiveCountdown.progress
    }

    /// How long the undo toast stays up.
    ///
    /// Injected rather than hard-coded because the window is untestable at a fixed length: a
    /// 5-second toast is a coin flip for a UI test on a loaded simulator, and a test that
    /// flakes is worse than no test, because it looks like coverage. A test passes a long
    /// window and the toast is simply there; production passes the default.
    let undoWindowDuration: TimeInterval

    @ObservationIgnored private lazy var archiveCountdown = PCTimeoutProgress(duration: undoWindowDuration)

    var isAnyCardEditing: Bool {
        cardViewModels.values.contains { $0.isEditing }
    }

    @ObservationIgnored private var cardViewModels: [Int64: PCCalendarCardViewModel] = [:]
    /// The calendar list's change feed. Ends when the view model deallocates: the
    /// loop's `guard let self` breaks, which terminates the task and releases the
    /// stream.
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    /// Reported when a calendar leaves the active set — archived, or deleted for good.
    ///
    /// Off the change feed rather than off the archive and delete methods, for two reasons. It
    /// is the *effect* rather than the intent, so a write that failed raises nothing here and
    /// the calendar stays where it was, which is the honest answer. And it covers every route to
    /// those operations — the card's button, the context menu, anything added later — instead of
    /// only the two this view happens to call today.
    ///
    /// `.removed` is exactly those two operations and not an approximation: they are the only
    /// ones that publish a removal, and a restore publishes a *change* instead.
    @ObservationIgnored
    var onCalendarRemoved: ((Int64) -> Void)?

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    public init(
        mode: CalendarListMode = .active,
        managing: any CalendarManaging,
        undoWindowDuration: TimeInterval = 5
    ) {
        self.mode = mode
        self.managing = managing
        self.undoWindowDuration = undoWindowDuration
        archiveCountdown.onComplete = { [weak self] in
            self?.undoWindowElapsed()
        }
        changesTask = Task { [weak self] in
            for await operation in await managing.changes() {
                guard let self else { return }
                self.applyChange(operation)
            }
        }
    }

    func cardViewModel(for calendar: PinCalendar) -> PCCalendarCardViewModel {
        if let existing = cardViewModels[calendar.id] {
            existing.name = calendar.name
            existing.numberOfColumns = calendar.numberOfColumns
            return existing
        }
        let vm = PCCalendarCardViewModel(id: calendar.id, name: calendar.name, numberOfColumns: calendar.numberOfColumns, isArchived: calendar.isArchived)
        vm.onEditCommitted = { [weak self] id, newName in
            self?.handleEditCommitted(id: id, newName: newName)
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

    /// Loads the list and reads the result directly.
    ///
    /// It does not wait for the `.refreshed` change the load just published. The change
    /// feed is a push channel with no replay, and this view model's subscription may not
    /// be live yet, so a first paint that awaited its own echo would intermittently come
    /// up empty — the bug that shape of API used to invite. `loadActive`/`loadArchived`
    /// hand back what they loaded, so there is nothing to wait for.
    ///
    /// The feed still earns its place: it carries writes made elsewhere, which arrive
    /// long after this subscription is established.
    func fetch() async {
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case .active: calendars = await managing.loadActive()
        case .archived: calendars = await managing.loadArchived()
        }
    }

    func addCalendar(with name: String) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.managing.createCalendar(name: name, year: 2026, numberOfColumns: 3)
            self.isLoading = false
        }
    }

    /// Archives the calendar immediately and shows an undo toast. The toast's
    /// progress bar is the 5s window during which the user can undo.
    func archiveCalendarInList(_ calendar: PinCalendar) {
        pendingArchive = calendar
        archiveToastMessage = "\(calendar.name) archived"
        isArchiveToastPresented = true
        archiveCountdown.start()
        Task { [weak self] in
            try? await self?.managing.archiveCalendar(id: calendar.id)
        }
    }

    /// Called when the undo window elapses — the calendar stays archived and
    /// the toast dismisses.
    func undoWindowElapsed() {
        pendingArchive = nil
        isArchiveToastPresented = false
        archiveCountdown.cancel()
    }

    /// Called when the user taps the toast's undo — restores the calendar and
    /// refreshes the active list so it reappears.
    func undoArchive() {
        guard let calendar = pendingArchive else { return }
        pendingArchive = nil
        isArchiveToastPresented = false
        archiveCountdown.cancel()
        // No re-read here. The restore publishes a change that `applyChange` folds in,
        // and this runs in the active list, where the restored calendar is visible. An
        // extra `loadActive()` would only discard its own result while also refreshing
        // the store's notion of which list is current.
        Task { [weak self] in
            try? await self?.managing.restoreCalendar(id: calendar.id)
        }
    }

    func restoreCalendarInList(_ calendar: PinCalendar) {
        Task { [weak self] in
            try? await self?.managing.restoreCalendar(id: calendar.id)
        }
    }

    func permanentlyDeleteCalendar(_ calendar: PinCalendar) {
        Task { [weak self] in
            try? await self?.managing.permanentlyDeleteCalendar(id: calendar.id)
        }
    }

    func addItem() {
        addEditCalendarViewModel.reset()
    }

    private func handleEditCommitted(id: Int64, newName: String) {
        Task { [weak self] in
            guard let self else { return }
            if var cal = self.calendars.first(where: { $0.id == id }) {
                cal.name = newName
                try? await self.managing.updateCalendar(cal)
            }
        }
    }

    /// Folds one change into the visible list.
    ///
    /// A store emits changes relative to *its own* current list, which is whichever
    /// active-or-archived set was loaded last — and that is not necessarily this view
    /// model's `mode`. Two cases make that visible: restoring a calendar while viewing
    /// Archived is reported as an addition, even though the result is that the calendar
    /// leaves this list; and a refresh can carry the other mode's contents. So instead
    /// of trusting the operation's shape, every change is resolved against `mode`:
    /// if the calendar belongs in the visible set it is upserted, otherwise it is taken
    /// out. That makes the view model correct against any store, and independent of
    /// which list the store happened to have loaded.
    private func applyChange(_ change: PinCalendarChange) {
        switch change {
        case let .refreshed(list):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                calendars = list.filter(isVisible)
            }
        case let .added(item), let .changed(item):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                if isVisible(item) {
                    if let idx = calendars.firstIndex(where: { $0.id == item.id }) {
                        calendars[idx] = item
                    } else {
                        calendars.append(item)
                    }
                } else {
                    calendars.removeAll { $0.id == item.id }
                }
            }
        case let .removed(item):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                calendars.removeAll { $0.id == item.id }
            }
            // Announced after the list has folded it in, so a handler that re-reads the list
            // sees the calendar already gone. Harmless either way, and cheaper to reason about
            // than one where the order matters.
            onCalendarRemoved?(item.id)
        }
    }

    /// Whether a calendar belongs in the list this view model is showing.
    private func isVisible(_ calendar: PinCalendar) -> Bool {
        switch mode {
        case .active: return !calendar.isArchived
        case .archived: return calendar.isArchived
        }
    }
}
