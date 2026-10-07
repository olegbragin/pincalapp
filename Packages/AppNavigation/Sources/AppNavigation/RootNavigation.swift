//
//  RootNavigation.swift
//  PinCalApp
//

import Foundation
import Observation
import os
import SwiftUI

/// Navigation state changes, logged.
///
/// This exists to answer one question on the iPad: when a calendar is selected, is
/// `preferredCompactColumn` actually `.detail` when the split view reads it, and does
/// something put it back? That is not answerable from the accessibility tree — the split
/// view's own state is not exposed — and it is not answerable by reasoning about
/// `NavigationSplitView`, which has its own opinions about compact width.
///
/// Deliberately **not** exposed through accessibility identifiers. A container's identifier
/// overrides its children's (see §19), so the obvious way to publish state to a UI test is
/// the very thing that cost 30 tests before. `os_log` cannot disturb the tree.
private let navLog = Logger(subsystem: "com.crucialsoftware.PinCalApp", category: "navigation")

/// Main-actor isolated because it *is* the UI's navigation state: every property here is read
/// during view rendering and written from a tap. Isolating it also makes the guarded switch
/// well-typed — `switchCalendar` suspends to consult the store's guard, and a `Task` that
/// inherits this isolation is not "sending" the navigation anywhere.
@MainActor
@Observable
public class RootNavigation {
    public init() {}
    public var selectedSidebarCategory: SidebarCategory? = .calendarList
    public var path = NavigationPath()

    /// Which column is shown when the split view collapses on iPhone.
    /// Setting `.detail` presents the detail column; the system flips it back
    /// when the user taps Back.
    public var preferredCompactColumn: NavigationSplitViewColumn = .sidebar {
        didSet {
            guard oldValue != preferredCompactColumn else { return }
            navLog.debug("preferredCompactColumn \(String(describing: oldValue)) -> \(String(describing: self.preferredCompactColumn))")
        }
    }

    public var isAtRoot: Bool {
        path.isEmpty
    }

    /// Pops the top of the navigation stack, if there is one.
    ///
    /// The reducer emits `.pop` as a `NavigationRequest` when a stage is left, and the
    /// view layer carries it out. There was no way to express that before: `goTo` only
    /// appends, and `popToRoot` is private and all-or-nothing. Without this, a back
    /// transition driven by state would have to clear the whole stack, which would drop
    /// the calendar detail too.
    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Current detail column selection (for split-view "open" navigation).
    ///
    /// `nil` means no calendar is on screen. That covers two things, and it used to cover only
    /// the first: before any calendar has ever been selected, and after the selected one is
    /// closed because it was archived or deleted (`closeCalendarIfSelected`).
    ///
    /// Leaving the calendar for a sidebar category does *not* clear it.
    ///
    /// It used to be nil'd on navigating to `.archived`/`.settings`, on the theory that the
    /// detail column should not keep showing a calendar you have navigated away from. That is
    /// wrong on a split view: the detail column is a peer of the content column, not a child of
    /// it, so browsing the archive or settings is expected to leave the detail in place. Worse,
    /// it made the detail column's contents depend on navigation history, so the same calendar
    /// would render or not render purely because of how you arrived — the sort of invisible
    /// coupling that only shows up on a wide layout.
    ///
    /// A calendar ceasing to exist is a different matter from walking away from it, which is why
    /// it gets the clearing that walking away does not. Left stale, it was a detail column
    /// showing a deleted calendar: the id survived, so the app root went on injecting that
    /// calendar's store, and the detail itself went blank (`SingleCalendarModel` fetches, finds
    /// nothing, and renders nothing) with no way back and no explanation.
    public private(set) var detailCalendarID: Int64?

    /// Gates leaving the current calendar, installed by whoever owns unsaved work.
    ///
    /// `RootNavigation` cannot know whether a write is in flight or has failed — that state
    /// lives in the feature's store, one layer down and in a different module. Rather than
    /// move that store into here (a large refactor for a two-line question), whoever owns the
    /// store registers a closure and the navigation asks it before switching away.
    ///
    /// Async because the answer is not known synchronously: settling an in-flight write means
    /// awaiting it. Returning `false` means the switch was refused and nothing happened.
    ///
    /// A nil guard is permissive — a calendar with no store has nothing to protect.
    ///
    /// `@MainActor` because the store's state is main-actor isolated, and it is captured by a
    /// `Task` that hops. Swift 6 rejects sending a non-Sendable class across that boundary
    /// otherwise, and the hop is not optional: the closure cannot be called synchronously.
    public var canLeaveCurrentCalendar: (@MainActor @Sendable () async -> Bool)?

    /// Runs when a calendar is being left, before the switch is carried out.
    ///
    /// The sibling of `canLeaveCurrentCalendar`, and it exists because a *question* is not
    /// enough. Leaving has a consequence that nothing else performs: ending the calendar's
    /// multi-select session, and deleting its batch if the user took every day back off.
    ///
    /// It was being done from the calendar detail's `onDisappear`, which covers Back on iPhone
    /// and a switch on iPad — but only when that view is actually torn down, and on iPad the
    /// detail column sometimes never loads. A session that outlives its calendar comes back
    /// painted and unendable, and the store is cached, so it comes back *populated*. Dispatching
    /// from the switch itself makes the lifetime a property of the switch rather than of a view
    /// teardown that may not happen.
    ///
    /// `@MainActor @Sendable` for the same reason as the guard above: the state it touches is
    /// main-actor isolated in a store one layer down.
    public var willLeaveCurrentCalendar: (@MainActor @Sendable () async -> Void)?

    /// Called with the new calendar id at the moment `detailCalendarID` changes, before the change.
    ///
    /// Installed by whoever owns the per-calendar state, so the app root can inject the right
    /// store for the calendar that is about to be shown. Synchronous and inside the mutation for
    /// the reason given at the call site: an observer would be a frame late, and this value
    /// chooses which store the whole subtree reads.
    ///
    /// **Optional** because closing a calendar is a change too, and a root that only learns
    /// about openings goes on injecting the store for a calendar that is no longer there. `nil`
    /// means "no calendar is on screen", which is the same answer the root needs before the
    /// first one is ever opened.
    public var onCalendarChanged: (@MainActor (Int64?) -> Void)?

    /// Closes `id` if it is the calendar on screen — because it was archived, or deleted for
    /// good, and so is no longer something to be looking at.
    ///
    /// A no-op for any other id, including when nothing is open. That guard is the whole reason
    /// this is a method on the navigation rather than a `detailCalendarID = nil` at the call
    /// site: the caller is reacting to a change feed that names *every* calendar that left the
    /// active set, and closing the detail because some *other* calendar was archived would
    /// throw away a screen the user never asked to leave.
    ///
    /// Three things happen, and the order is the point:
    ///
    /// 1. **The leave hook runs first**, while `detailCalendarID` still names the calendar — the
    ///    hook reads it to find the store whose multi-select session is being ended. A cached
    ///    store means a session that outlives its calendar comes back painted and unendable, and
    ///    this is one of the ways a calendar stops being on screen without a switch.
    /// 2. **The pushed stack is cleared.** It belongs to that calendar: leaving `.batchEditor`
    ///    on the stack while the detail shows the "select a calendar" placeholder would build
    ///    that editor against a calendar that is gone.
    /// 3. **The id is cleared, after `onCalendarChanged(nil)`** — for the same reason an opening
    ///    notifies before it assigns. The root injects a store chosen by this value, so telling
    ///    it afterwards would leave one render built against the calendar being closed.
    ///
    /// The write guard is deliberately **not** consulted. `switchCalendar` asks because an
    /// unsaved edit must not be abandoned by walking away from it; here the calendar is being
    /// archived or erased, so settling its write chain would mean writing to a row that is on
    /// its way out. There is nothing to protect and something to avoid.
    ///
    /// Undoing an archive does not reopen it. The calendar comes back to the *list*, and
    /// selecting it again is the user's decision to look at it — a detail that reappeared on its
    /// own would be the detail deciding what the user is looking at.
    public func closeCalendarIfSelected(_ id: Int64) async {
        guard detailCalendarID == id else { return }
        await willLeaveCurrentCalendar?()
        popToRoot()
        onCalendarChanged?(nil)
        detailCalendarID = nil
    }

    /// Set when a link could not be honoured, and cleared when the alert is dismissed.
    ///
    /// Navigation state for the same reason `presentedSheet` is: it is a thing on screen that the
    /// user has to answer, and it outlives the call that raised it. Optional rather than a
    /// `Bool` plus a `String`, which is two pieces of state that can disagree — the pattern this
    /// codebase already has in `archiveToastMessage` / `isArchiveToastPresented`.
    public var deepLinkFailure: DeepLinkFailure?

    /// Records that a link could not be honoured, and puts the user somewhere they can act.
    ///
    /// One operation rather than a bare state write, because the two halves belong together: a
    /// link that failed leaves the user looking at whatever was open before, which reads as the
    /// tap having done nothing, so the alert is much easier to notice if the screen has also
    /// changed underneath it.
    public func reportDeepLinkFailure(_ failure: DeepLinkFailure) async {
        deepLinkFailure = failure
        await showCalendarListWithoutSelection()
    }

    /// Lands on the calendar list with nothing selected — where a link that names no calendar
    /// leaves the user.
    ///
    /// A link is a request to be shown a calendar. When the one it names is not there, the choices
    /// are to ignore the link or to show the list, and ignoring is the worse of the two: the user
    /// asked for a calendar and would be left looking at whatever was open before, which reads as
    /// the tap having done nothing at all. The list says "there is nothing to open" in a way they
    /// can act on, and it is where they were trying to go anyway.
    ///
    /// Both halves are needed and neither is enough alone. The category alone would leave the
    /// detail column still showing a calendar, so the list and the detail would disagree about
    /// what is selected; the close alone would leave the user on Settings with an empty detail.
    ///
    /// The close goes through `closeCalendarIfSelected` rather than assigning the id, because
    /// that is the only thing that can clear it — and it is what ends the calendar's multi-select
    /// session, which a cached store would otherwise bring back painted and unendable.
    ///
    /// Inert when nothing is open, which is the ordinary outcome for a bad link arriving into a
    /// fresh launch: the category is already the list and there is no calendar to close.
    public func showCalendarListWithoutSelection() async {
        goTo(.sidebar(.calendarList))
        if let id = detailCalendarID {
            await closeCalendarIfSelected(id)
        }
    }

    /// Switches to `calendarID` only if the guard allows it.
    ///
    /// This is the only supported way to change calendars, because it is the only place the
    /// guard is consulted. A caller that reaches for `goTo(.calendar(id, toRoot: true))`
    /// directly gets no protection at all, which is why the calendar list routes through here
    /// instead of doing it by hand.
    public func switchCalendar(to id: Int64) async {
        // Deliberately a suspension point rather than a synchronous check. Settling a write
        // means awaiting it, and a guard that could only answer "right now, from memory"
        // would answer `true` for every write still in the chain — which is exactly the writes
        // that get abandoned when the session tears down.
        if let canLeaveCurrentCalendar, await canLeaveCurrentCalendar() == false {
            return
        }
        // The switch was allowed, so this calendar is actually being left — end its session
        // before the route changes, while the store for it is still the one on screen.
        await willLeaveCurrentCalendar?()
        goTo(.calendar(id, toRoot: true))
    }

    /// Currently presented sheet
    public private(set) var presentedSheet: AppRoute?

    /// Unified navigation — single entry point for all routes.
    /// The route itself (via AppRoute.navigationStyle) defines how to navigate.
    public func goTo(_ route: AppRoute) {
        navLog.debug("goTo \(String(describing: route)) detailCalendarID=\(String(describing: self.detailCalendarID)) category=\(String(describing: self.selectedSidebarCategory))")
        switch route {
        // MARK: - Sidebar category selection (changes content column)

        case let .sidebar(category):
            selectedSidebarCategory = category
            // detailCalendarID intentionally left untouched: the detail column is a peer of the
            // content column, so switching category does not dismiss the detail.

        // MARK: - Open (split-view detail column replacement)

        case let .calendar(id, toRoot):
            if toRoot {
                popToRoot()
            }
            // Told *before* the state changes, not from an `onChange` on the view that observes
            // it. An observer runs after the render that acted on the new value, so whatever it
            // feeds is one frame stale — and the app root injects the current calendar's store
            // from that value, so a frame of staleness means the calendar detail is built with
            // one store while every view reads another. The symptom is a day list that opens and
            // is empty. Setting it here makes the two agree by construction.
            onCalendarChanged?(id)
            detailCalendarID = id
            preferredCompactColumn = .detail
            presentedSheet = nil

        // MARK: - Push (navigation stack)

        case .dayBatches:
            path.append(route)

        case .batchEditor:
            path.append(route)

        case .eventEditor:
            path.append(route)

        // MARK: - Present (sheet)

        case .addCalendar:
            presentedSheet = route
        }
    }

    /// Dismiss presented sheet
    public func dismissSheet() {
        presentedSheet = nil
    }

    /// Clear navigation stack (pop to root). Only callable internally — callers
    /// should use `goTo(.calendar(id, toRoot: true))` to open a calendar and
    /// return to its root in one step.
    private func popToRoot() {
        path = NavigationPath()
    }
}
