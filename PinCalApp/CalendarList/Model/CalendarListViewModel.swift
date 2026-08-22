//
//  CalendarListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Observation
import Foundation

enum CalendarListMode {
    case active
    case archived
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
    let mode: CalendarListMode

    var calendars: [CalendarDataSource] = []
    var displayMode: DisplayMode = .list

    var addEditCalendarViewModel = AddEditCalendarViewModel()
    var isAddEditSheetPresented = false
    var isLoading = false

    var isAnyCardEditing: Bool {
        cardViewModels.values.contains { $0.isEditing }
    }

    @ObservationIgnored private var cardViewModels: [Int64: PCCalendarCardViewModel] = [:]
    @ObservationIgnored private var calendarObserver: AnyObject?
    @ObservationIgnored private var suppressObserver = false

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    init(mode: CalendarListMode = .active, manager: CalendarManager = .init()) {
        self.mode = mode
        self.manager = manager
        calendarObserver = manager.subscribeToCalendars { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard !self.suppressObserver else { return }
                try? await self.fetch()
            }
        }
    }

    func cardViewModel(for calendar: CalendarDataSource) -> PCCalendarCardViewModel {
        if let existing = cardViewModels[calendar.id] {
            existing.name = calendar.name
            existing.numberOfColumns = calendar.numberOfColumns
            return existing
        }
        let vm = PCCalendarCardViewModel(calendar: calendar)
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

    func fetch() async throws {
        let fetched: [CalendarDataSource]
        switch mode {
        case .active: fetched = try await manager.getActiveCalendars()
        case .archived: fetched = try await manager.getArchivedCalendars()
        }
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

    func archiveCalendarInList(_ calendar: CalendarDataSource) {
        guard let idx = calendars.firstIndex(where: { $0.id == calendar.id }) else { return }
        calendars.remove(at: idx)
        suppressObserver = true
        Task { [weak self] in
            guard let self else { return }
            try? await self.manager.archiveCalendar(calendar.id)
            self.suppressObserver = false
        }
    }

    func restoreCalendarInList(_ calendar: CalendarDataSource) {
        guard let idx = calendars.firstIndex(where: { $0.id == calendar.id }) else { return }
        calendars.remove(at: idx)
        suppressObserver = true
        Task { [weak self] in
            guard let self else { return }
            try? await self.manager.restoreCalendar(calendar.id)
            self.suppressObserver = false
        }
    }

    func permanentlyDeleteCalendar(_ calendar: CalendarDataSource) {
        guard let idx = calendars.firstIndex(where: { $0.id == calendar.id }) else { return }
        calendars.remove(at: idx)
        suppressObserver = true
        Task { [weak self] in
            guard let self else { return }
            try? await self.manager.deleteCalendar(calendar.id)
            self.suppressObserver = false
        }
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
}
