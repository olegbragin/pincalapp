//
//  PCEventSelectionNavigator.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 29.09.2026.
//

import Foundation
import AppNavigation

/// The one place a `NavigationRequest` becomes navigation.
///
/// The reducer is pure, so it cannot touch a navigation stack — it says what should
/// happen and this carries it out. Keeping that in one file is the point: when three
/// screens each had their own `onChange` doing a `switch` over the target they drifted,
/// and a fourth kind of request would have been implemented in one of them and missed in
/// the others.
///
/// `.pop` lives here rather than being expressed as an `AppRoute` because it is the one
/// target that is not a destination — it removes the top of the stack.
@MainActor
public enum PCEventSelectionNavigator {
    /// Carries out `request`, then acknowledges it.
    ///
    /// The acknowledgement is not optional bookkeeping. A request's `id` is derived from
    /// whatever is still pending, so leaving one unacknowledged makes the next one
    /// indistinguishable from it — and the screen that fulfils it is the only place that
    /// knows it happened.
    ///
    /// ### Why the request is re-read rather than trusted
    ///
    /// A pushed screen does not replace the one beneath it, so two mounted screens can see the
    /// same `onChange`. The value `onChange` hands them is a *capture*, taken before either ran,
    /// so both would consider themselves the fulfiller and the pop would happen twice — landing
    /// the user one screen too far back. The event editor was the screen that used to sit on
    /// top and make this a live problem; the guard stays because the day list is still pushed
    /// under the batch editor's sheet.
    ///
    /// Re-reading the store's *current* request instead makes fulfilment atomic: the first
    /// screen to get here acts and clears it, and any other screen finds nothing pending
    /// and stands down. That is the same "exactly one listener acts" rule the day-tap
    /// callback follows, applied to navigation.
    public static func fulfil(
        _ request: NavigationRequest,
        calendarID: Int64,
        using navigation: RootNavigation,
        in store: PCEventSelectionManager
    ) {
        guard store.state.navigationRequest == request else { return }

        switch request.target {
        case .pushDayList:
            navigation.goTo(.dayBatches)
        case .presentBatchEditor:
            navigation.goTo(.batchEditor)
        case .pop:
            navigation.pop()
        case .dismissBatchEditor:
            // The batch editor is a sheet, so leaving it dismisses that sheet. `dismissSheet()`
            // and not an assignment: `presentedSheet` is `private(set)`, and a route that set
            // it directly would let a second caller clear a sheet the first one still meant
            // to be showing.
            //
            // This is deliberately not `pop()`. `pop()` removes the top of the
            // `NavigationStack`, and the editor was never pushed onto it — so `pop()` would
            // hit `guard !path.isEmpty` and return having done nothing, leaving Back as a
            // button that visibly does nothing.
            navigation.dismissSheet()
        case .popToCalendarRoot:
            // Reopening the calendar at its root is how "leave the assembly line" is
            // expressed: it clears the pushed stack without closing the calendar itself.
            navigation.goTo(.calendar(calendarID, toRoot: true))
        }
        store.send(.navigationRequestHandled)
    }
}
