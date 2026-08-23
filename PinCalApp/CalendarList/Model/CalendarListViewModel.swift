//
//  CalendarListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Observation
import Foundation
import Combine
import SwiftUI

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
    private let cache: CalendarCache
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
    @ObservationIgnored private var cancellable: AnyCancellable?

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    init(mode: CalendarListMode = .active, cache: CalendarCache) {
        self.mode = mode
        self.cache = cache
        cancellable = cache.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] operation in
                self?.applyChange(operation)
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

    func fetch() async {
        switch mode {
        case .active: await cache.loadActive()
        case .archived: await cache.loadArchived()
        }
    }

    func addCalendar(with name: String) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.cache.createCalendar(name: name, year: 2026, numberOfColumns: 3)
            self.isLoading = false
        }
    }

    func archiveCalendarInList(_ calendar: CalendarDataSource) {
        Task { [weak self] in
            try? await self?.cache.archiveCalendar(calendar)
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
        isAddEditSheetPresented = true
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
