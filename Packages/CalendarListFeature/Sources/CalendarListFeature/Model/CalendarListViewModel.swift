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

    /// A load that failed, cleared by the next successful one.
    ///
    /// Held as state because "the list is empty" and "the list could not be read" are different
    /// facts and a view cannot tell them apart by looking at `calendars`. Before this existed the
    /// difference was destroyed rather than represented: a failed read returned `[]`, so a
    /// transient database error presented as *your calendars are gone* — and, because the cache
    /// assigned that empty list over its own state, the in-memory copy was destroyed too.
    ///
    /// Deliberately not an `Error`. What failed is this package's business; what to *say* about
    /// it belongs to whoever presents it, exactly as `PCFailedSave` separates its stored message
    /// from the wording `SingleCalendarView` shows.
    var loadFailure = false

    /// A write that failed, cleared by the next successful one or by retrying.
    ///
    /// Separate from `loadFailure` because the two have different shapes and different remedies:
    /// a failed *read* is worth retrying exactly as-is, whereas a failed *write* has to be retried
    /// as the specific operation it was — and a permanent delete must be asked for again rather
    /// than replayed by a generic retry.
    var writeFailure: PCCalendarListWriteFailure?

    /// Records a failed write. The last one wins.
    ///
    /// Last-wins rather than first-wins because each failure carries its own retry, and offering
    /// a retry for something that has since failed differently would replay the wrong operation.
    func recordWriteFailure(_ failure: PCCalendarListWriteFailure) {
        writeFailure = failure
    }

    /// Re-runs the failed write, exactly as it was attempted.
    ///
    /// Not "whatever the user last asked for": the archive undo and the rename are different
    /// operations with different payloads, and a retry that re-derived them from current state
    /// could write something other than what failed.
    func retryWriteFailure() {
        guard let failure = writeFailure else { return }
        // Cleared before awaiting, so a failure that recurs is recorded afresh rather than
        // leaving a stale one that a later success would wrongly clear.
        writeFailure = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                switch failure.operation {
                case let .create(name):
                    try await self.managing.createCalendar(name: name, year: 2026, numberOfColumns: 3)
                case let .rename(calendarID, newName):
                    guard var cal = self.calendars.first(where: { $0.id == calendarID }) else { return }
                    cal.name = newName
                    try await self.managing.updateCalendar(cal)
                case let .archive(calendarID):
                    try await self.managing.archiveCalendar(id: calendarID)
                case let .restore(calendarID):
                    try await self.managing.restoreCalendar(id: calendarID)
                case let .permanentlyDelete(calendarID):
                    try await self.managing.permanentlyDeleteCalendar(id: calendarID)
                }
            } catch {
                self.recordWriteFailure(
                    .init(
                        operation: failure.operation,
                        calendarName: failure.calendarName,
                        message: error.pcUserFacingDescription
                    )
                )
            }
        }
    }

    /// Records a failed load, keeping whatever was already on screen.
    ///
    /// Not clearing `calendars` is the point. A failed read is not evidence that the user has no
    /// calendars, so the last known list stays visible behind the error rather than being
    /// replaced by a blank one that reads as data loss.
    func recordLoadFailure() {
        isLoading = false
        loadFailure = true
    }

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
    ///
    /// Throws if the load fails, leaving `calendars` untouched — that is the behaviour the
    /// throws bought — and records the failure in `loadFailure` on the way out.
    ///
    /// It both records *and* rethrows. Recording alone would hide the failure from a caller that
    /// wants to react differently, and rethrowing alone would leave the view layer with no way
    /// to tell this apart from a merely-stale list. A caller that wants neither simply discards
    /// the error, exactly as it did before.
    func fetch() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .active: calendars = try await managing.loadActive()
            case .archived: calendars = try await managing.loadArchived()
            }
        } catch {
            recordLoadFailure()
            throw error
        }
        // Only reached when the load succeeded, so a stale failure cannot outlive the fix.
        loadFailure = false
    }

    func addCalendar(with name: String) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                try await self.managing.createCalendar(name: name, year: 2026, numberOfColumns: 3)
            } catch {
                // The create sheet has already dismissed by this point — it validates the name
                // and closes, never having touched storage — so without this the user is left
                // with a dismissed sheet, a cleared spinner and no calendar, having been told
                // nothing.
                self.recordWriteFailure(
                    .init(operation: .create(name: name), calendarName: nil, message: error.pcUserFacingDescription)
                )
            }
        }
    }

    /// Archives the calendar and shows an undo toast once the write has landed.
    ///
    /// The toast used to be presented *before* the write was attempted, which made the claim
    /// "X archived" an assertion the code had not yet earned. A failed write left the calendar
    /// sitting in the active list under a banner saying it had been archived, and the five-second
    /// Undo window counted down over a change that had not happened.
    ///
    /// Now the write is awaited first. The undo window starts when there is genuinely something
    /// to undo — so on failure there is no toast, no countdown, and no false claim, and the
    /// calendar stays exactly where it was.
    func archiveCalendarInList(_ calendar: PinCalendar) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.managing.archiveCalendar(id: calendar.id)
            } catch {
                self.recordWriteFailure(
                    .init(
                        operation: .archive(calendarID: calendar.id),
                        calendarName: calendar.name,
                        message: error.pcUserFacingDescription
                    )
                )
                return
            }
            self.pendingArchive = calendar
            self.archiveToastMessage = "\(calendar.name) archived"
            self.isArchiveToastPresented = true
            self.archiveCountdown.start()
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
    ///
    /// A failed restore is now reported rather than silent. This was the worst of the six: the
    /// user was told the calendar was archived, tapped Undo, and if the restore then threw the
    /// calendar stayed archived with the toast gone and nothing said. Both halves of the undo had
    /// appeared to work and neither had.
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
            guard let self else { return }
            do {
                try await self.managing.restoreCalendar(id: calendar.id)
            } catch {
                self.recordWriteFailure(
                    .init(
                        operation: .restore(calendarID: calendar.id),
                        calendarName: calendar.name,
                        message: error.pcUserFacingDescription
                    )
                )
            }
        }
    }

    func restoreCalendarInList(_ calendar: PinCalendar) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.managing.restoreCalendar(id: calendar.id)
            } catch {
                self.recordWriteFailure(
                    .init(
                        operation: .restore(calendarID: calendar.id),
                        calendarName: calendar.name,
                        message: error.pcUserFacingDescription
                    )
                )
            }
        }
    }

    /// The only irreversible write in the app.
    ///
    /// There is no undo and no recovery, which is why the failure is recorded as this specific
    /// operation: retrying a permanent delete has to be a decision the user makes again, not
    /// something a generic "try again" replays for them.
    ///
    /// Note what does *not* happen on failure — nothing broadcasts a removal. The removal change
    /// comes from the cache, and the cache's list is updated on the write's success path, so a
    /// thrown delete leaves the calendar on screen and `onCalendarRemoved` un-fired. That
    /// ordering is deliberate and this is where it is load-bearing: had the cache removed the
    /// row regardless, the failure would still have closed the detail column and cleared the
    /// selection, tearing down a screen over a row that never went anywhere.
    func permanentlyDeleteCalendar(_ calendar: PinCalendar) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.managing.permanentlyDeleteCalendar(id: calendar.id)
            } catch {
                self.recordWriteFailure(
                    .init(
                        operation: .permanentlyDelete(calendarID: calendar.id),
                        calendarName: calendar.name,
                        message: error.pcUserFacingDescription
                    )
                )
            }
        }
    }

    func addItem() {
        addEditCalendarViewModel.reset()
    }

    private func handleEditCommitted(id: Int64, newName: String) {
        Task { [weak self] in
            guard let self else { return }
            guard var cal = self.calendars.first(where: { $0.id == id }) else { return }
            cal.name = newName
            do {
                try await self.managing.updateCalendar(cal)
            } catch {
                // The card already shows the new name — `PCCalendarCardViewModel` mutated its
                // own copy before calling this — so on failure the row is labelled with a name
                // that is not in storage, and the *next* successful write for this calendar
                // would carry it forward and overwrite the stored one.
                //
                // The stored name is put back so what is on screen matches what is on disk.
                self.revertRenamedCard(id: id, to: newName)
                self.recordWriteFailure(
                    .init(operation: .rename(calendarID: id, newName: newName), calendarName: newName, message: error.pcUserFacingDescription)
                )
            }
        }
    }

    /// Undoes the optimistic rename in the card that shows it.
    private func revertRenamedCard(id: Int64, to rejectedName: String) {
        guard let original = calendars.first(where: { $0.id == id }), original.name != rejectedName else { return }
        cardViewModels[id]?.restoreName(original.name)
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
