//
//  CalendarListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Observation
import Foundation
import SwiftUI
import CorePersistence
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
    private let cache: CalendarCache
    let mode: CalendarListMode

    var calendars: [CalendarDataSource] = []
    var displayMode: DisplayMode = .list

    var addEditCalendarViewModel = AddEditCalendarViewModel()
    var isLoading = true

    /// Calendar awaiting the archive timeout; nil when no toast is pending.
    var pendingArchive: CalendarDataSource?
    var isArchiveToastPresented = false
    var archiveToastMessage = ""
    var archiveToastProgress: Double { archiveCountdown.progress }

    @ObservationIgnored private let archiveCountdown = PCTimeoutProgress(duration: 5)

    var isAnyCardEditing: Bool {
        cardViewModels.values.contains { $0.isEditing }
    }

    @ObservationIgnored private var cardViewModels: [Int64: PCCalendarCardViewModel] = [:]
    /// The calendar list's change feed. Ends when the view model deallocates: the
    /// loop's `guard let self` breaks, which terminates the task and releases the
    /// stream.
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    public init(mode: CalendarListMode = .active, cache: CalendarCache) {
        self.mode = mode
        self.cache = cache
        archiveCountdown.onComplete = { [weak self] in
            self?.undoWindowElapsed()
        }
        changesTask = Task { [weak self] in
            for await operation in await cache.changes() {
                guard let self else { return }
                self.applyChange(operation)
            }
        }
    }

    func cardViewModel(for calendar: CalendarDataSource) -> PCCalendarCardViewModel {
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

    /// Loads the list and reads the result back.
    ///
    /// It does not wait for the `.refresh` broadcast that `loadActive`/`loadArchived`
    /// just sent. The change feed is a push channel with no replay, and this view
    /// model's subscription may not be live yet, so a first paint that awaited its own
    /// echo would intermittently come up empty. The feed still earns its place: it
    /// carries writes made elsewhere, which arrive long after this subscription is
    /// established.
    func fetch() async {
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case .active: await cache.loadActive()
        case .archived: await cache.loadArchived()
        }
        calendars = await cache.loadedCalendars()
    }

    func addCalendar(with name: String) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.cache.createCalendar(name: name, year: 2026, numberOfColumns: 3)
            self.isLoading = false
        }
    }

    /// Archives the calendar immediately and shows an undo toast. The toast's
    /// progress bar is the 5s window during which the user can undo.
    func archiveCalendarInList(_ calendar: CalendarDataSource) {
        pendingArchive = calendar
        archiveToastMessage = "\(calendar.name) archived"
        isArchiveToastPresented = true
        archiveCountdown.start()
        Task { [weak self] in
            try? await self?.cache.archiveCalendar(calendar)
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
        Task { [weak self] in
            try? await self?.cache.restoreCalendar(calendar)
            await self?.cache.loadActive()
        }
    }

    func restoreCalendarInList(_ calendar: CalendarDataSource) {
        Task { [weak self] in
            try? await self?.cache.restoreCalendar(calendar)
        }
    }

    func permanentlyDeleteCalendar(_ calendar: CalendarDataSource) {
        Task { [weak self] in
            try? await self?.cache.permanentlyDeleteCalendar(calendar)
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
                try? await self.cache.updateCalendar(cal)
            }
        }
    }

    private func applyChange(_ operation: ChangeOperation) {
        switch operation {
        case .refresh(let calendars):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                self.calendars = calendars
            }
        case .add(let item):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                calendars.append(item)
            }
        case .delete(let item):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                calendars.removeAll { $0.id == item.id }
            }
        case .change(let item):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                if let idx = calendars.firstIndex(where: { $0.id == item.id }) {
                    calendars[idx] = item
                }
            }
        }
    }
}
