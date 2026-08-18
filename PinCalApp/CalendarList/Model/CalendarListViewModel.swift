//
//  CalendarListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Observation

enum PendingChange: Equatable {
    case removed(CalendarDataSource, originalIndex: Int)
    case edited(id: Int64, oldName: String, newName: String)
}

@Observable
final class CalendarListViewModel {
    private var manager: CalendarManager
    
    var calendars: [CalendarDataSource] = []
    
    var addEditCalendarViewModel = AddEditCalendarViewModel()
    var isAddEditSheetPresented = false
    var isLoading = false
    
    var editingCalendarID: Int64?
    var editingCalendarName: String = ""
    
    private(set) var pendingChanges: [PendingChange] = []
    var hasPendingChanges: Bool { !pendingChanges.isEmpty }
    
    init(manager: CalendarManager = .init()) {
        self.manager = manager
    }
    
    func fetch() async throws {
        let fetched = try await manager.getAllCalendars()
        if fetched != self.calendars {
            self.calendars = fetched
        }
    }
    
    func commitChanges() {
        if let editingCalendarID, let idx = pendingChanges.firstIndex(where: {
            if case .edited(let eid, _, _) = $0 { return eid == editingCalendarID }
            return false
        }) {
            if case .edited(let eid, let oldName, _) = pendingChanges[idx] {
                pendingChanges[idx] = .edited(id: eid, oldName: oldName, newName: editingCalendarName)
            }
            if let calIdx = calendars.firstIndex(where: { $0.id == editingCalendarID }) {
                calendars[calIdx].name = editingCalendarName
            }
        }
        for change in pendingChanges {
            switch change {
            case .removed(let cal, _):
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.manager.deleteCalendar(cal.id)
                }
            case .edited(let id, _, let newName):
                if var calendar = calendars.first(where: { $0.id == id }) {
                    calendar.name = newName
                    Task { [weak self] in
                        guard let self else { return }
                        try? await self.manager.updateCalendar(calendar)
                    }
                }
            }
        }
        pendingChanges.removeAll()
        editingCalendarID = nil
        editingCalendarName = ""
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
    
    func removeCalendar(_ calendar: CalendarDataSource) {
        Task { [weak self] in
            guard let self else { return }
            try await manager.deleteCalendar(calendar.id)
            await MainActor.run {
                self.calendars.removeAll { $0.id == calendar.id }
            }
        }
    }
    
    func removeCalendarFromDeck(_ calendar: CalendarDataSource) {
        guard let idx = calendars.firstIndex(where: { $0.id == calendar.id }) else { return }
        let removed = calendars.remove(at: idx)
        pendingChanges.append(.removed(removed, originalIndex: idx))
    }
    
    func startEditing(_ calendar: CalendarDataSource) {
        if let currentID = editingCalendarID, currentID != calendar.id {
            _confirmCurrentEdit()
        }
        guard editingCalendarID != calendar.id else { return }
        if !pendingChanges.contains(where: {
            if case .edited(let id, _, _) = $0 { return id == calendar.id }
            return false
        }) {
            pendingChanges.append(.edited(id: calendar.id, oldName: calendar.name, newName: calendar.name))
        }
        editingCalendarID = calendar.id
        editingCalendarName = calendar.name
    }
    
    func confirmEdit() {
        _confirmCurrentEdit()
        editingCalendarID = nil
        editingCalendarName = ""
    }
    
    private func _confirmCurrentEdit() {
        guard let id = editingCalendarID else { return }
        if let idx = calendars.firstIndex(where: { $0.id == id }) {
            calendars[idx].name = editingCalendarName
        }
        if let changeIdx = pendingChanges.firstIndex(where: {
            if case .edited(let eid, _, _) = $0 { return eid == id }
            return false
        }) {
            if case .edited(let eid, let oldName, _) = pendingChanges[changeIdx] {
                pendingChanges[changeIdx] = .edited(id: eid, oldName: oldName, newName: editingCalendarName)
            }
        }
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
            if case .edited(let id, let oldName, _) = change {
                if let idx = calendars.firstIndex(where: { $0.id == id }) {
                    calendars[idx].name = oldName
                }
            }
        }
        
        if editingCalendarID != nil {
            editingCalendarID = nil
            editingCalendarName = ""
        }
    }
    
    func addItem() {
        addEditCalendarViewModel.reset()
        isAddEditSheetPresented = true
    }
}
