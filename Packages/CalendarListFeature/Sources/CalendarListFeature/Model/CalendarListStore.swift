//
//  CalendarListStore.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 14.10.2026.
//

import Foundation
import CoreDomain
import DSKit

/// The single owner of `CalendarListState`, and the only thing that talks to the port.
///
/// The same shape as `PCEventSelectionManager`: one `send`, a pure reducer deciding what an
/// action means, and a second pure function saying what the world should be told. Nothing
/// outside this type assigns `state`.
///
/// Effects run in a `Task` rather than being awaited by `send`, because every caller is a
/// synchronous view command — a button, a context menu — and making the UI await a write would
/// put storage on the path of a user's tap. A failed write comes back as an action
/// (`.writeFailed`) rather than as a throw, so the outcome re-enters through the same funnel
/// as the intent.
@MainActor
@Observable
public final class CalendarListStore {
    /// The whole of the screen's state. Everything the UI reads is either here or projected
    /// from it, so there is one place to look and nothing can disagree with itself.
    public private(set) var state: CalendarListState

    @ObservationIgnored private let managing: any CalendarManaging

    /// How long the undo toast stays up.
    ///
    /// Injected rather than hard-coded because the window is untestable at a fixed length: a
    /// 5-second toast is a coin flip for a UI test on a loaded simulator, and a test that
    /// flakes is worse than no test, because it looks like coverage.
    @ObservationIgnored public let undoWindowDuration: TimeInterval

    /// The archive window's clock. A timer, so it cannot live in the `Equatable` state.
    ///
    /// Its completion is fed back in as `.undoWindowElapsed` rather than mutating state here,
    /// so ending the window is still a transition the reducer decides on.
    @ObservationIgnored private lazy var archiveCountdown = PCTimeoutProgress(duration: undoWindowDuration)

    /// A calendar left the visible set — archived, or deleted for good.
    ///
    /// Off the change feed rather than off the archive and delete methods, for two reasons. It
    /// is the *effect* rather than the intent, so a write that failed raises nothing here and
    /// the calendar stays where it was, which is the honest answer. And it covers every route to
    /// those operations — the card's button, the context menu, anything added later — instead
    /// of only the ones this screen happens to call today.
    @ObservationIgnored public var onCalendarRemoved: ((Int64) -> Void)?

    /// Told when a load fails, with the error that came back.
    ///
    /// Raised by the failing effect rather than through an action, because `CalendarListState`
    /// has to stay `Equatable` and an `Error` is neither `Equatable` nor something a
    /// transition should be described by.
    @ObservationIgnored public var onLoadFailed: ((any Error) -> Void)?

    /// Told when a write fails, with the failure that has to be retried.
    @ObservationIgnored public var onWriteFailed: ((PCCalendarListWriteFailure) -> Void)?

    /// A rename was rejected, so an optimistically-shown card name must be put back.
    ///
    /// Raised by the store because it owns the failure, and handled by the panel because it
    /// owns the card view models — the same division as the three callbacks above.
    @ObservationIgnored public var onRenameRejected: ((Int64, String) -> Void)?

    /// The calendar list's change feed. Ends when the store deallocates: the loop's
    /// `guard let self` breaks, which terminates the task and releases the stream.
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    public init(
        mode: CalendarListMode,
        managing: any CalendarManaging,
        undoWindowDuration: TimeInterval = 5
    ) {
        self.state = CalendarListState(mode: mode)
        self.managing = managing
        self.undoWindowDuration = undoWindowDuration
        archiveCountdown.onComplete = { [weak self] in
            self?.send(.undoWindowElapsed)
        }
        changesTask = Task { [weak self] in
            for await change in await managing.changes() {
                guard let self else { return }
                self.send(.changeApplied(change))
            }
        }
    }

    // MARK: - The one mutation point

    /// The single funnel every state change goes through.
    ///
    /// State is committed before effects are issued so an effect reads the state the views
    /// are already showing, and a rejected action — one whose transition returns the state
    /// unchanged — runs no effect at all rather than issuing a pointless write.
    public func send(_ action: CalendarListAction) {
        let previous = state
        let next = commit(action)
        for effect in calendarListEffects(action, previous, next) {
            perform(effect)
        }
    }

    /// Reads the list, and reports whether it worked.
    ///
    /// Awaits and rethrows, unlike every other command here. Two callers need the outcome:
    /// the refresh gesture, whose spinner is held until the closure returns and would otherwise
    /// be stranded; and the view's `.task`, which would otherwise have to be the one place that
    /// does not await. One method with one contract beats two entry points that disagree about
    /// whether a load is finished.
    ///
    /// Deliberately does not go through `send`, so it does not also issue the `.load` effect
    /// and read the list twice.
    ///
    /// The one path that bypasses the effect chain, and deliberately: it has to await and
    /// rethrow, which a queued effect cannot do — the caller is holding a refresh gesture's
    /// spinner. The window is narrow and harmless. A read interleaved with a queued write can
    /// only return the value from before it, and the write's own broadcast on the change feed
    /// corrects the list a moment later. Making this ordered too would mean a queued write
    /// could delay the very gesture that has to feel immediate.
    public func fetch() async throws {
        commit(.loadStarted)
        try await load()
    }

    /// Applies an action's transition without running its effects. Returns the new state so
    /// `send` can hand both it and the previous one to `calendarListEffects`.
    @discardableResult
    private func commit(_ action: CalendarListAction) -> CalendarListState {
        let previous = state
        let next = calendarListReducer(previous, action)
        if next != previous {
            state = next
        }
        return next
    }

    // MARK: - Executing effects

    /// The last effect issued, so the next one can wait for it. See `perform`.
    @ObservationIgnored private var effectTail: Task<Void, Never>?

    /// Queues an effect behind every effect already issued.
    ///
    /// Chained rather than spawned, because the alternative is not ordered and the port is not
    /// safe to interleave. Every write in `CalendarCache` is a read-modify-write split by an
    /// `await` — `archiveCalendar` awaits the repository and *then* prunes its list — so a
    /// second call can land between the two halves. `restoreCalendar`'s refetch is the case
    /// that bites: an archive interleaving there makes the restore append an archived calendar
    /// back into the active list. Unstructured tasks make that a race the user wins or loses by
    /// tapping fast; the chain makes it unrepresentable.
    ///
    /// This is the same argument as the write chain in the persistence layer, and the same
    /// warning: a bare `Task { }` here would put storage on a path with no ordering.
    ///
    /// Deliberately *not* `async`. `send` has to stay synchronous because most of its callers
    /// are — a `Button` action, and the card view model's `onDelete` / `onRestore` /
    /// `onPermanentDelete` closures. Making `perform` `async` would make `send` `async`, and
    /// every one of those callers would then wrap the call in a `Task { }`: the same
    /// unstructured concurrency, one level up, and still unordered. Chaining fixes ordering
    /// without forcing a single caller to become asynchronous.
    ///
    /// Strong `self`, so a queued write runs even if the screen goes away mid-flight. A write
    /// the user already asked for is not one that may be dropped because a view disappeared.
    private func perform(_ effect: CalendarListEffect) {
        let previous = effectTail
        effectTail = Task {
            await previous?.value
            await run(effect)
        }
    }

    private func run(_ effect: CalendarListEffect) async {
        switch effect {
        case .load:
            try? await load()

        case let .createCalendar(name):
            await create(named: name)

        case let .renameCalendar(calendarID, newName):
            await rename(calendarID: calendarID, to: newName)

        case let .archiveCalendar(calendarID):
            await archive(calendarID: calendarID)

        case let .restoreCalendar(calendarID):
            await restore(calendarID: calendarID)

        case let .permanentlyDeleteCalendar(calendarID):
            await permanentlyDelete(calendarID: calendarID)

        case let .announceRemoval(id):
            onCalendarRemoved?(id)

        case .cancelArchiveWindow:
            archiveCountdown.cancel()
        }
    }

    // MARK: - Reads

    /// How much of the archive window is left, for the toast's progress bar.
    ///
    /// Read from the timer rather than stored, because it moves every frame and state is
    /// compared for equality on every transition — a countdown ticking through it would make
    /// every unrelated action look like a change.
    public var archiveToastProgress: Double {
        archiveCountdown.progress
    }

    /// Loads the list for this screen's mode and reports the result back as an action.
    ///
    /// It does not wait for the `.refreshed` change the load just published. The change feed
    /// is a push channel with no replay, and this subscription may not be live yet, so a first
    /// paint that awaited its own echo would intermittently come up empty — the bug that shape
    /// of API used to invite. The load hands back what it loaded, so there is nothing to wait
    /// for. The feed still earns its place: it carries writes made elsewhere.
    private func load() async throws {
        do {
            let loaded: [PinCalendar]
            switch state.mode {
            case .active: loaded = try await managing.loadActive()
            case .archived: loaded = try await managing.loadArchived()
            }
            send(.loadSucceeded(loaded))
        } catch {
            send(.loadFailed)
            onLoadFailed?(error)
            // Rethrown so `refresh` can take the gesture's spinner down. The `.loadStarted`
            // effect discards it; nothing has to handle it on that path.
            throw error
        }
    }

    // MARK: - Writes

    private func create(named name: String) async {
        do {
            try await managing.createCalendar(name: name, year: 2026, numberOfColumns: 3)
            // No `.loadSucceeded` here: the create publishes a change the feed folds in, and
            // re-reading would discard its own result.
        } catch {
            // The create sheet has already dismissed by this point — it validates the name and
            // closes, never having touched storage — so without this the user is left with a
            // dismissed sheet, a cleared spinner and no calendar, having been told nothing.
            fail(.create(name: name), calendarName: nil, error: error)
        }
    }

    private func rename(calendarID: Int64, to newName: String) async {
        guard var calendar = state.calendars.first(where: { $0.id == calendarID }) else { return }
        calendar.name = newName
        do {
            try await managing.updateCalendar(calendar)
        } catch {
            // The card already shows the new name — `PCCalendarCardViewModel` mutated its own
            // copy before calling this — so on failure the row is labelled with a name that is
            // not in storage, and the *next* successful write for this calendar would carry it
            // forward and overwrite the stored one. Putting the stored name back is what makes
            // what is on screen match what is on disk.
            onRenameRejected?(calendarID, newName)
            fail(.rename(calendarID: calendarID, newName: newName), calendarName: newName, error: error)
        }
    }

    private func archive(calendarID: Int64) async {
        guard let calendar = state.calendars.first(where: { $0.id == calendarID }) else { return }
        do {
            try await managing.archiveCalendar(id: calendarID)
            // Only now. The toast used to be presented *before* the write was attempted, which
            // made "X archived" an assertion the code had not yet earned — and left a failed
            // write counting five seconds of Undo over a change that had not happened.
            send(.archiveConfirmed(calendar))
            archiveCountdown.start()
        } catch {
            fail(.archive(calendarID: calendarID), calendarName: calendar.name, error: error)
        }
    }

    /// Undoes an archive, or restores a calendar tapped in the archived list.
    ///
    /// The name lookup is optional on purpose, and the two callers are why. Undoing an archive
    /// fires this for a calendar that has *already left this list* — the archived change took
    /// it out of view — so requiring it to be present would have made Undo silently do nothing
    /// on exactly the path it exists for. The name is only needed to phrase a failure.
    private func restore(calendarID: Int64) async {
        let name = state.calendars.first(where: { $0.id == calendarID })?.name
        do {
            try await managing.restoreCalendar(id: calendarID)
        } catch {
            fail(.restore(calendarID: calendarID), calendarName: name, error: error)
        }
    }

    /// The only irreversible write in the app.
    ///
    /// There is no undo and no recovery, which is why the failure is recorded as this specific
    /// operation: retrying a permanent delete has to be a decision the user makes again, not
    /// something a generic "try again" replays for them.
    ///
    /// Note what does *not* happen on failure — nothing announces a removal. The removal change
    /// comes from the cache, and the cache's list is updated on the write's success path, so a
    /// thrown delete leaves the calendar on screen and `onCalendarRemoved` un-fired.
    private func permanentlyDelete(calendarID: Int64) async {
        let name = state.calendars.first(where: { $0.id == calendarID })?.name
        do {
            try await managing.permanentlyDeleteCalendar(id: calendarID)
        } catch {
            fail(.permanentlyDelete(calendarID: calendarID), calendarName: name, error: error)
        }
    }

    /// Records a failed write. The last one wins.
    ///
    /// Last-wins rather than first-wins because each failure carries its own retry, and
    /// offering a retry for something that has since failed differently would replay the wrong
    /// operation.
    ///
    /// `onWriteFailed` is raised from here rather than observed from `state.writeFailure`, and
    /// that is the whole reason this helper exists. Observing a state change cannot see two
    /// identical failures in a row, because the value did not move — so "it failed, I retried,
    /// it failed again" lost its second report, which is the case a diagnostics table most
    /// needs to show. Every write funnels through this one call, so no entry point can forget.
    private func fail(
        _ operation: PCCalendarListWriteFailure.Operation,
        calendarName: String?,
        error: any Error
    ) {
        let failure = PCCalendarListWriteFailure(
            operation: operation,
            calendarName: calendarName,
            message: error.pcUserFacingDescription
        )
        send(.writeFailed(failure))
        onWriteFailed?(failure)
    }
}
