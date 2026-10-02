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

    public var isAtRoot: Bool { path.isEmpty }

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
    /// `nil` means *no calendar has ever been selected* — nothing else. Leaving the calendar
    /// for a sidebar category does not clear it.
    ///
    /// It used to be nil'd on navigating to `.archived`/`.settings`, on the theory that the
    /// detail column should not keep showing a calendar you have navigated away from. That is
    /// wrong on a split view: the detail column is a peer of the content column, not a child of
    /// it, so browsing the archive or settings is expected to leave the detail in place. Worse,
    /// it made the detail column's contents depend on navigation history, so the same calendar
    /// would render or not render purely because of how you arrived — the sort of invisible
    /// coupling that only shows up on a wide layout.
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
        case .sidebar(let category):
            selectedSidebarCategory = category
            // detailCalendarID intentionally left untouched: the detail column is a peer of the
            // content column, so switching category does not dismiss the detail.
            
        // MARK: - Open (split-view detail column replacement)
        case .calendar(let id, let toRoot):
            if toRoot {
                popToRoot()
            }
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
