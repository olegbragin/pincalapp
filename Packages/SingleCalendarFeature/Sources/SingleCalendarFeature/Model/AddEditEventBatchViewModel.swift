//
//  AddEditEventBatchViewModel.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 02.07.2026.
//

import Foundation
import SwiftUI
import CoreDomain
import DSKit

/// A projection facade over the store for the batch editor.
///
/// This used to hold `eventBatchId`, `eventBatchName`, `date`, `timestamp` and a whole
/// `eventBatch` alongside the shared manager, then assembled an `EventBatchDataSource` by
/// hand to commit — four copies of one pending batch, one of them a DTO the feature layer
/// is not supposed to name. All of it is `state.assembly` now, so there is nowhere for a
/// second copy to live.
///
/// A plain `struct`, not `@Observable`: the store is the only observable object in the
/// flow. Reading `canSave` during `body` evaluation records the read on `store.state`, so
/// any `send` re-renders the view. A stored copy would be a second thing that can be
/// stale, which is the class of bug this stage exists to remove.
@MainActor
public struct AddEditEventBatchViewModel {
    private let store: PCEventSelectionManager

    init(store: PCEventSelectionManager) {
        self.store = store
    }

    // MARK: - Projections

    private var batch: CalendarEventBatch? {
        store.state.assembly?.batch
    }

    var name: String {
        batch?.name ?? ""
    }

    /// What the empty field offers instead. The suggestion, not a value: a batch is created
    /// unnamed so that a misclick writes nothing, and pre-filling the field would put the name
    /// back on its behalf the moment the user touched anything else.
    var namePlaceholder: String {
        PCEventBatchAssembleUnitOfWork.defaultBatchName
    }

    var events: [CalendarEvent] {
        batch?.events ?? []
    }

    var isEmpty: Bool {
        events.isEmpty
    }

    /// The colour the picker opens on: the batch's own, or failing that its first event's,
    /// so a batch built from multi-selected days does not open on a colour that
    /// contradicts what is already on screen.
    var defaultColor: PCColorOption? {
        if let colorName = batch?.colorName, !colorName.isEmpty {
            return PCColorOption(colorName)
        }
        return batch?.events.first.flatMap { PCColorOption($0.colorName) }
    }

    /// The editor's calendar. A render target projected from the state by the store, not a
    /// copy of it — the day-model instances here are the ones the views bind to.
    var yearModel: PCCalendarYearModel {
        store.yearModel
    }

    var preferredTitle: String? {
        title(compact: false)
    }

    var compactTitle: String? {
        title(compact: true)
    }

    // MARK: - Two-way controls

    var nameBinding: Binding<String> {
        Binding(get: { name }, set: { store.send(.setBatchName($0)) })
    }

    var colorBinding: Binding<PCColorOption?> {
        Binding(get: { defaultColor }, set: { store.send(.setBatchColor($0)) })
    }

    // MARK: - Event time

    /// The selected events, in the assembly's order. A derivation, so it cannot disagree
    /// with the selection it claims to describe.
    var selectedEvents: [CalendarEvent] {
        store.state.selectedEvents
    }

    /// Whether the time picker has anything to act on.
    ///
    /// Disabled rather than hidden with an empty selection. A picker that is on screen and
    /// does nothing is worse than one that explains itself, but a picker that *appears* the
    /// moment a row is selected moves the layout under the user's finger — so it stays put
    /// and greys out.
    var isTimePickerEnabled: Bool {
        !selectedEvents.isEmpty
    }

    /// The time the picker shows: the first selected event's own.
    ///
    /// Showing the first event's time rather than a separate draft is what makes the control
    /// honest about what a pick will do — it opens on what is already stored, so turning the
    /// wheel without changing it changes nothing. When the selection holds events with
    /// *different* times the control shows the first and the next pick overwrites all of them
    /// with it; that is a limitation of `DatePicker` having no "mixed" state, not a rule worth
    /// reimplementing, and the alternative — showing something that is not stored — would be
    /// worse.
    var displayedEventTime: Date {
        if let first = selectedEvents.first {
            return first.date
        }
        // Nothing selected: the batch's own first event, so opening the editor does not show
        // today's clock next to events that are at midnight. A disabled control showing an
        // unrelated instant is still a value the user could read as the current one.
        if let first = events.first {
            return first.date
        }
        return store.state.day ?? Date()
    }

    /// Writes `time` to every selected event — the whole of what the picker does.
    ///
    /// It is a method and not a `Binding`'s `set` on purpose. A binding commits on every tick
    /// of the wheel it wraps, which is a gesture, not a decision; this is called once, when
    /// the user says they are finished with it. See `PCEventTimePicker`.
    func applyTime(_ time: Date) {
        store.send(.applyTimeToSelectedEvents(time))
    }

    // MARK: - Commands

    func switchYear(to year: Int) {
        store.send(.setEditorYear(year))
    }

    // MARK: - Titles

    private func title(compact: Bool) -> String? {
        let dates = events.map(\.date).sorted()
        guard let start = dates.first else {
            return store.state.day.map { singleDate($0, compact: compact) }
        }
        guard let end = dates.last, end > start else {
            return singleDate(start, compact: compact)
        }
        if compact {
            return compactPeriod(from: start, to: end)
        }
        return "\(fullDate(start)) - \(fullDate(end))"
    }

    private func singleDate(_ date: Date, compact: Bool) -> String {
        compact
            ? date.formatted(date: .numeric, time: .omitted)
            : fullDate(date)
    }

    private func fullDate(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.abbreviated))
        let year = calendar.component(.year, from: date)
        return "\(day) \(month) \(year)"
    }

    private func compactPeriod(from start: Date, to end: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let startDay = start.formatted(.dateTime.day())
        let endDay = end.formatted(.dateTime.day())
        if calendar.component(.month, from: start) == calendar.component(.month, from: end),
           calendar.component(.year, from: start) == calendar.component(.year, from: end)
        {
            return "\(startDay)-\(endDay) \(end.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return "\(startDay) \(start.formatted(.dateTime.month(.abbreviated))) - \(endDay) \(end.formatted(.dateTime.month(.abbreviated).year()))"
    }
}
