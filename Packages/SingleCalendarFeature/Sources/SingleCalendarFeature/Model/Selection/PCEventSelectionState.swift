//
//  PCEventSelectionState.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// Where the user is on the assembly line. One enum rather than a navigation stack,
/// because the line has a fixed order and the state says which room we are in.
///
/// Three rooms, and there used to be four. `.eventEditor` went with the screen itself: it
/// existed to carry the two ids a pushed editor needed to know what it was editing, and with
/// nothing to push there is nothing for the pair to identify.
public enum PCEventSelectionStage: Equatable {
    case idle
    case dayList(day: Date)
    case batchEditor

    /// The day the day-list is scoped to, or `nil` when the session is elsewhere.
    ///
    /// For assertions about *which day list* the user is returned to, rather than about
    /// the stage's shape. It is deliberately `nil` for the other cases rather than
    /// reporting something adjacent, so a test that means "the list for this day" cannot
    /// quietly pass against a state that is not a day list.
    public var asDayList: Date? {
        if case let .dayList(day) = self {
            return day
        }
        return nil
    }
}

/// A navigation the *view layer* should carry out, derived by the reducer rather than
/// performed by it. The reducer is pure, so it cannot touch a navigation stack; it says
/// what should happen and the store executes it (§7.2).
public struct NavigationRequest: Equatable {
    /// Distinguishes this request from a previous one. A pure reducer has no clock and no
    /// counter, so the id is derived: one more than whatever is pending, which is 1 after
    /// `navigationRequestHandled` cleared the last one. It only has to separate requests
    /// that are still pending, not identify them across time.
    public let id: Int
    public let target: Target

    public enum Target: Equatable {
        case pushDayList
        /// The batch editor is a sheet, so this is `.presentBatchEditor` and not a push.
        case presentBatchEditor
        case pop
        /// Leaving the batch editor, which dismisses its sheet.
        ///
        /// Distinct from `.pop` rather than reusing it. Both used to mean the same thing —
        /// the batch editor was pushed — and merging them again would make the target depend
        /// on which stage the user happened to be in: `.pop` removes the top of the
        /// `NavigationStack`, and for a route that was never pushed that is
        /// `RootNavigation.pop()`'s `guard !path.isEmpty` returning without doing anything.
        /// Back in the editor would then be a button that visibly does nothing, which is the
        /// one failure mode the editor's explicit Back exists to avoid (it is there because
        /// the system's never reaches the store). One target per way out keeps each
        /// unambiguous about what it removes.
        case dismissBatchEditor
        case popToCalendarRoot
    }
}

/// The whole of the batch-assembly feature's state, as a value.
///
/// Mutated only by `pcEventSelectionReducer`. Everything the UI reads is either stored
/// here or derived from it by the two computed properties at the bottom, so there is one
/// place to look and nothing can disagree with itself.
public struct PCEventSelectionState: Equatable {
    // MARK: Assembly line

    public var stage: PCEventSelectionStage = .idle
    public var assembly: PCEventBatchAssembleUnitOfWork?
    /// No `eventDraft` here. It was the event editor's working copy — a copy of an edit that
    /// `persistEventDraft` folded back into the assembly on every keystroke — so the copy and
    /// the real thing were the same value held twice. With the editor gone there is one.
    /// The day the day-list is scoped to, and the anchor the assembly scrolls to.
    public var day: Date?

    // MARK: Committed registry — a mirror of the persisted calendar

    public var calendarID: Int64 = 0
    public var batches: [CalendarEventBatch] = []

    // MARK: Editor calendar

    public var editorYear: Int?
    public var numberOfColumns: Int = 3
    public var scrollAnchor: Date?
    /// Day-marker payload: start-of-day → colour names. Stored rather than derived
    /// because the staged assembly is *not* in `batches`, so the marker set during an
    /// edit differs from the committed one. The year model is projected from this after
    /// every action (§7.3).
    public var dayEventColors: [Date: [String]] = [:]

    // MARK: Main-calendar multi-select session

    public var multiSelectMode = false
    public var multiSelectDays: [Date] = []
    /// The colour the multi-select session is building its batch in. `nil` until the user
    /// picks one, and an assembly cannot be confirmed without it — which is why this field
    /// and `confirmMultiSelectTapped` were both deferred to Stage 7, where `PCColorOption`
    /// becomes `Equatable` and a state carrying one can still be compared with `==`.
    public var multiSelectColor: PCColorOption?

    /// The batch the multi-select session is building, created on the first tapped day and
    /// then *reused* for every tap after it.
    ///
    /// Identity is the whole point. A batch merges into the registry by `mergeKey`, which is
    /// `persistedID ?? pending(pendingID)` — so a batch rebuilt from scratch on each tap gets
    /// a fresh `pendingID`, a different key, and lands beside the previous one instead of
    /// replacing it. Tapping two days produced two batches, both covering day 17. Holding one
    /// assembly for the session keeps its key stable, so each tap updates the batch the last
    /// tap wrote.
    ///
    /// Kept separate from `assembly` because that one belongs to the batch editor, and a
    /// session that is selecting days is not editing a batch.
    public var multiSelectAssembly: PCEventBatchAssembleUnitOfWork?

    // MARK: Event selection inside the batch editor

    /// Whether the event list is selecting.
    ///
    /// **Nothing reads this to decide what a row does any more.** It was there because a row
    /// was the only tap target for two different things — "include this one" while selecting and
    /// "open this one" otherwise — and the view had to know which. The event editor is gone and
    /// the row is a card, so a tap can only mean "include this one".
    ///
    /// It is kept rather than removed because it still answers a question the selection
    /// *cannot*: whether the ids in `selectedEventIDs` are the ones the user meant, or leftovers
    /// from a set they have since put down. `toggleEventSelection` sets it, and `false` on the
    /// toggle clears both together, so an empty selection and "not selecting" stay
    /// distinguishable. Deleting it would mean inferring the mode from the set being non-empty,
    /// which is the exact conflation this field exists to prevent.
    public var isSelectingEvents = false

    /// Which of the assembly's events are selected, by `pendingID`.
    ///
    /// **`pendingID`, not `Date`.** Day identity is deliberately day-granular everywhere else
    /// in this feature, which makes a date a natural key — and it is the wrong one here,
    /// because these are exactly the events that *have* a time of day. Two events can share a
    /// day, and the whole point of the feature is to set a time on several of them at once, so
    /// a date-keyed selection could not say *which* events on a day the time applies to.
    /// `pendingID` is the identity that is stable for the edit's lifetime: these events live
    /// inside the staged assembly, which is never rebuilt from a DTO, so their ids survive
    /// every reload (the same argument that carries `removeEvent`).
    public var selectedEventIDs: Set<UUID> = []

    /// The selected events, in the assembly's order.
    ///
    /// A derivation rather than a second stored array, for the reason `editorDayEventColors`
    /// is one: a stored copy is a thing that can disagree with the assembly it claims to
    /// describe. Ordering comes from the assembly, which is already sorted by date, so the
    /// result does not depend on the order the user tapped in — which matters because the
    /// first of them is what the time picker displays.
    public var selectedEvents: [CalendarEvent] {
        guard !selectedEventIDs.isEmpty else { return [] }
        return assembly?.batch.events.filter { selectedEventIDs.contains($0.pendingID) } ?? []
    }

    // MARK: Environment the reducer needs (§5.1)

    public var dataProvider: PCCalendarDataProvider

    // MARK: Intent

    /// Set by a name edit: this change reached `batches` but the store owes a write for it.
    ///
    /// The reducer cannot debounce — it is a pure function, and "wait a quarter second" is
    /// not a transition. So it records *that* a write is owed and leaves the timing to the
    /// store, which is where effects already run. Every other merge writes immediately.
    ///
    /// Read and cleared by the store; it is not a property of the state a screen renders.
    public var persistsAsTyped = false

    /// Whether the last write landed.
    ///
    /// `isDirty` used to sit next to this: written in 21 places by the reducer, read nowhere
    /// in production. Only tests read it, so it asserted that a transition had happened rather
    /// than that the app behaved correctly — the assertion could not fail on its own. "Has this
    /// been saved" is answered by `PCEventSelectionManager.failedSave`, which is the only flag
    /// anything acts on, and it is set from whether the write actually succeeded rather than
    /// from whether something was attempted.
    public var didSave = false
    /// Pending navigation for the view layer. Cleared by `navigationRequestHandled`.
    public var navigationRequest: NavigationRequest?

    public init(dataProvider: PCCalendarDataProvider = PCCalendarDataProvider()) {
        self.dataProvider = dataProvider
    }

    // MARK: - Derivations

    /// The marker payload for the **batch editor's** calendar: the batch being edited, and
    /// nothing else.
    ///
    /// A second payload rather than a narrower reading of `dayEventColors`, because the two
    /// answer different questions. The main panel asks "which days hold anything", and the
    /// answer is every batch in the registry. The editor asks "which days does *this* batch
    /// hold", and every other batch's days are not merely noise there — they are
    /// indistinguishable from this batch's, which is worse. Tapping a marked day in the
    /// editor calls `toggling`, which only knows about the assembly: a day another batch
    /// holds is *added* to this one, not removed from it. So a stranger's days drawn in the
    /// editor's calendar were days that looked switchable and were not.
    ///
    /// Reported as the assembly being reused across sessions. It was not — `assembly` is a
    /// fresh one-day batch every time an empty day is tapped, and the editor's event list
    /// reads nothing else. The calendar above the list was showing the whole calendar.
    ///
    /// Empty when there is no assembly, which is every stage but the batch editor's: the
    /// editor's calendar is not on screen, and a payload describing batches nobody is
    /// editing would only be waiting to be read as one.
    public var editorDayEventColors: [Date: [String]] {
        guard let assembly else { return [:] }
        return PCCalendarMarkerProjector.colorsByDay(from: [assembly.batch], using: dataProvider)
    }

    /// The committed batches that fall on `day`, in date order.
    public var dayBatches: [CalendarEventBatch] {
        guard let day else { return [] }
        return batches
            .filter { $0.occurs(on: day, using: dataProvider) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
}
