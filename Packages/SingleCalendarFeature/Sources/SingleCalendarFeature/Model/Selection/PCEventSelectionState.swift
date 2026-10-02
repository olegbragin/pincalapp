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
public enum PCEventSelectionStage: Equatable {
    case idle
    case dayList(day: Date)
    case batchEditor
    /// The two ids travel in the stage, not just in the draft, so a back button or a
    /// deep link can identify the pair without reconstructing it from the assembly.
    case eventEditor(batchPendingID: UUID, eventPendingID: UUID)

    /// The day the day-list is scoped to, or `nil` when the session is elsewhere.
    ///
    /// For assertions about *which day list* the user is returned to, rather than about
    /// the stage's shape. It is deliberately `nil` for the other cases rather than
    /// reporting something adjacent, so a test that means "the list for this day" cannot
    /// quietly pass against a state that is not a day list.
    public var asDayList: Date? {
        if case .dayList(let day) = self { return day }
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
        case pushBatchEditor
        case pushEventEditor
        case pop
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
    /// The event under edit while `stage == .eventEditor`. It lives outside the assembly
    /// because it is not yet part of the batch — the batch only gains it on
    /// `saveEventTapped`.
    public var eventDraft: CalendarEvent?
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

    // MARK: Environment the reducer needs (§5.1)

    public var dataProvider: PCCalendarDataProvider

    // MARK: Intent

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

    /// The committed batches that fall on `day`, in date order.
    public var dayBatches: [CalendarEventBatch] {
        guard let day else { return [] }
        return batches
            .filter { $0.occurs(on: day, using: dataProvider) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    public var canSave: Bool { assembly?.canSave ?? false }
}
