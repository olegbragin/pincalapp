//
//  CalendarListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Observation
import Foundation

enum PendingChange: Equatable {
    case removed(CalendarDataSource, originalIndex: Int)
}

enum DisplayMode: String, CaseIterable {
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
final class CalendarListViewModel {
    private var manager: CalendarManager

    var calendars: [CalendarDataSource] = []
    var displayMode: DisplayMode = .list

    var addEditCalendarViewModel = AddEditCalendarViewModel()
    var isAddEditSheetPresented = false
    var isLoading = false

    private(set) var pendingChanges: [PendingChange] = []
    var hasPendingChanges: Bool { !pendingChanges.isEmpty }

    var isAnyCardEditing: Bool {
        cardViewModels.values.contains { $0.isEditing }
    }

    @ObservationIgnored private var cardViewModels: [Int64: PCCalendarCardViewModel] = [:]
    @ObservationIgnored private var calendarObserver: AnyObject?

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    init(manager: CalendarManager = .init()) {
        self.manager = manager
        calendarObserver = manager.subscribeToCalendars { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                try? await self.fetch()
            }
        }
    }

    func cardViewModel(for calendar: CalendarDataSource) -> PCCalendarCardViewModel {
        if let existing = cardViewModels[calendar.id] {
            return existing
        }
        let vm = PCCalendarCardViewModel(calendar: calendar)
        vm.onEditCommitted = { [weak self] id, newName in
            self?.handleEditCommitted(id: id, newName: newName)
        }
        vm.onDelete = { [weak self] in
            guard let self else { return }
            self.removeCalendarFromList(calendar)
        }
        cardViewModels[calendar.id] = vm
        return vm
    }

    func fetch() async throws {
        let fetched = try await manager.getAllCalendars()
        self.calendars = fetched
        for calendar in calendars {
            cardViewModels[calendar.id]?.numberOfColumns = calendar.numberOfColumns
        }
    }

    func addCalendar(with name: String) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            let newCalendar = try await manager.createCalendar(name: name, year: 2026, numberOfColumns: 3)
            await MainActor.run {
                self.calendars.append(newCalendar)
                self.isLoading = false
            }
        }
    }

    func removeCalendarFromList(_ calendar: CalendarDataSource) {
        guard let idx = calendars.firstIndex(where: { $0.id == calendar.id }) else { return }
        let removed = calendars.remove(at: idx)
        pendingChanges.append(.removed(removed, originalIndex: idx))
    }

    func undoLastChange() {
        guard let last = pendingChanges.popLast() else { return }
        _undoChanges([last])
    }

    func undoAllChanges() {
        let changes = pendingChanges
        pendingChanges.removeAll()
        _undoChanges(changes)
    }

    func commitPendingRemovals() {
        for change in pendingChanges {
            if case .removed(let cal, _) = change {
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.manager.deleteCalendar(cal.id)
                }
            }
        }
        pendingChanges.removeAll()
    }

    func addItem() {
        addEditCalendarViewModel.reset()
        isAddEditSheetPresented = true
    }

    private func handleEditCommitted(id: Int64, newName: String) {
        if let calIdx = calendars.firstIndex(where: { $0.id == id }) {
            calendars[calIdx].name = newName
            let calendarToUpdate = calendars[calIdx]
            Task { [weak self] in
                guard let self else { return }
                try? await self.manager.updateCalendar(calendarToUpdate)
            }
        }
    }

    private func _undoChanges(_ changes: [PendingChange]) {
        let removals = changes.compactMap {
            if case .removed(let cal, let idx) = $0 { return (cal, idx) }
            return nil
        }.sorted { $0.1 < $1.1 }

        var result: [CalendarDataSource] = []
        var i = 0, j = 0
        while i < calendars.count && j < removals.count {
            if i < removals[j].1 {
                result.append(calendars[i]); i += 1
            } else {
                result.append(removals[j].0); j += 1
            }
        }
        result.append(contentsOf: calendars[i...])
        result.append(contentsOf: removals[j...].map(\.0))
        calendars = result

        for change in changes {
            if case .removed(let cal, _) = change {
                if let vm = cardViewModels[cal.id] {
                    vm.cancelEdit()
                }
            }
        }
    }
}
