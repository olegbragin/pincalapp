import Testing
import Foundation
@testable import AppNavigation

@Suite("RootNavigation Tests")
struct RootNavigationTests {
    
    // MARK: - Initial State Tests
    
    @Test("Initial state has calendarList selected and empty path")
    @MainActor
    func initialState() {
        let nav = RootNavigation()
        
        #expect(nav.selectedSidebarCategory == .calendarList)
        #expect(nav.isAtRoot == true)
        #expect(nav.detailCalendarID == nil)
        #expect(nav.presentedSheet == nil)
        #expect(nav.preferredCompactColumn == .sidebar)
    }
    
    // MARK: - Sidebar Navigation Tests
    
    @Test("goTo sidebar calendarList sets category")
    @MainActor
    func goToSidebarCalendarList() {
        let nav = RootNavigation()
        nav.goTo(.sidebar(.calendarList))
        
        #expect(nav.selectedSidebarCategory == .calendarList)
        #expect(nav.detailCalendarID == nil)
    }
    
    @Test("goTo sidebar archived sets category and keeps the detail calendar")
    @MainActor
    func goToSidebarArchived() {
        let nav = RootNavigation()
        // First set a detail calendar
        nav.goTo(.calendar(42, toRoot: false))
        #expect(nav.detailCalendarID == 42)
        
        // Now switch to archived
        nav.goTo(.sidebar(.archived))
        
        #expect(nav.selectedSidebarCategory == .archived)
        // The detail column is a peer of the content column, not a child: browsing the archive
        // must not tear down what the detail column is showing.
        #expect(nav.detailCalendarID == 42)
    }
    
    @Test("switchCalendar consults the guard, and a refusal does not switch")
    @MainActor
    func switchCalendarConsultsGuard() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(1, toRoot: false))

        var asked = 0
        nav.canLeaveCurrentCalendar = {
            asked += 1
            return false
        }

        await nav.switchCalendar(to: 2)

        #expect(asked == 1, "the guard is what decides, so it must be consulted")
        #expect(nav.detailCalendarID == 1, "a refused switch leaves the calendar alone")
    }

    @Test("switchCalendar switches when the guard allows it, and resets the stack")
    @MainActor
    func switchCalendarProceedsWhenAllowed() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(1, toRoot: false))
        nav.goTo(.dayBatches)

        nav.canLeaveCurrentCalendar = { true }

        await nav.switchCalendar(to: 2)

        #expect(nav.detailCalendarID == 2)
        #expect(nav.path.isEmpty, "selecting from the list resets the detail to its root")
    }

    /// Leaving a calendar has a consequence, not just a permission: the calendar's multi-select
    /// session ends, and its batch goes if the user took every day back off.
    ///
    /// It used to happen only in the detail view's `onDisappear`, which covers Back on iPhone and
    /// a switch on iPad — but only when that view is torn down, and on iPad the detail column
    /// sometimes never loads. Dispatching from the switch makes the session's lifetime a property
    /// of the switch rather than of a teardown that may not happen.
    @Test("switchCalendar runs the leave hook, and only once the guard has allowed the switch")
    @MainActor
    func switchCalendarRunsTheLeaveHook() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(1, toRoot: false))

        var asked = 0
        var left = 0
        nav.canLeaveCurrentCalendar = {
            asked += 1
            return true
        }
        nav.willLeaveCurrentCalendar = { left += 1 }

        await nav.switchCalendar(to: 2)

        #expect(asked == 1)
        #expect(left == 1, "the session is ended on the way out")
        #expect(nav.detailCalendarID == 2)
    }

    /// A refused switch leaves nothing behind. Ending the session first would throw away a
    /// selection the user is still looking at and did not agree to end.
    @Test("A refused switch does not end the session")
    @MainActor
    func refusedSwitchDoesNotRunTheLeaveHook() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(1, toRoot: false))

        var left = 0
        nav.canLeaveCurrentCalendar = { false }
        nav.willLeaveCurrentCalendar = { left += 1 }

        await nav.switchCalendar(to: 2)

        #expect(left == 0, "the calendar was not left, so its session is not over")
        #expect(nav.detailCalendarID == 1)
    }

    /// No hook installed is the ordinary case for anything that is not a calendar detail, and it
    /// must not be a crash or a stall.
    @Test("No leave hook means there is nothing to end")
    @MainActor
    func switchCalendarWithoutALeaveHook() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(1, toRoot: false))

        await nav.switchCalendar(to: 2)

        #expect(nav.detailCalendarID == 2)
    }

    @Test("No guard means the switch is allowed — nothing to protect")
    @MainActor
    func switchCalendarWithoutAGuard() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(1, toRoot: false))

        await nav.switchCalendar(to: 2)

        #expect(nav.detailCalendarID == 2)
    }

    @Test("detailCalendarID stays nil until a calendar has been selected")
    @MainActor
    func detailCalendarIDNilUntilFirstSelection() {
        let nav = RootNavigation()
        
        // Every sidebar category, before any calendar is ever opened.
        for category in [AppNavigation.SidebarCategory.calendarList, .archived, .settings] {
            nav.goTo(.sidebar(category))
            #expect(nav.detailCalendarID == nil)
        }
        
        // Once one is selected it survives leaving, for good.
        nav.goTo(.calendar(7, toRoot: false))
        #expect(nav.detailCalendarID == 7)
        for category in [AppNavigation.SidebarCategory.calendarList, .archived, .settings] {
            nav.goTo(.sidebar(category))
            #expect(nav.detailCalendarID == 7)
        }
    }
    
    // MARK: - Calendar Detail Tests
    
    @Test("goTo calendar sets detailCalendarID and preferredCompactColumn")
    @MainActor
    func goToCalendar() {
        let nav = RootNavigation()
        nav.goTo(.calendar(123, toRoot: false))
        
        #expect(nav.detailCalendarID == 123)
        #expect(nav.preferredCompactColumn == .detail)
        #expect(nav.presentedSheet == nil)
    }
    
    @Test("goTo calendar clears presented sheet")
    @MainActor
    func goToCalendarClearsSheet() {
        let nav = RootNavigation()
        nav.goTo(.addCalendar)
        #expect(nav.presentedSheet == .addCalendar)
        
        nav.goTo(.calendar(456, toRoot: false))
        
        #expect(nav.presentedSheet == nil)
        #expect(nav.detailCalendarID == 456)
    }
    
    // MARK: - Push Navigation Tests
    
    @Test("goTo dayBatches appends to path")
    @MainActor
    func goToDayBatches() {
        let nav = RootNavigation()

        nav.goTo(.dayBatches)
        
        #expect(nav.path.count == 1)
    }
    
    @Test("goTo batchEditor appends to path")
    @MainActor
    func goToBatchEditor() {
        let nav = RootNavigation()

        nav.goTo(.batchEditor)

        #expect(nav.path.count == 1)
    }

    @Test("goTo eventEditor appends to path")
    @MainActor
    func goToEventEditor() {
        let nav = RootNavigation()

        nav.goTo(.eventEditor)

        #expect(nav.path.count == 1)
    }
    
    @Test("Multiple push routes accumulate in path")
    @MainActor
    func multiplePushRoutes() {
        let nav = RootNavigation()
        
        nav.goTo(.dayBatches)
        nav.goTo(.batchEditor)
        
        #expect(nav.path.count == 2)
    }
    
    // MARK: - Closing a calendar that has been archived or deleted

    /// Archiving or deleting the calendar on screen must close it.
    ///
    /// It used to leave the id in place, so the detail column went on naming a calendar that was
    /// no longer there: the app root kept injecting that calendar's store, and the detail itself
    /// rendered nothing at all — `SingleCalendarModel` fetches, finds no calendar, and `.empty`
    /// draws an `EmptyView`. Blank column, stale id, no way back.
    @Test("Closing the selected calendar clears the detail")
    @MainActor
    func closingTheSelectedCalendarClearsTheDetail() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))

        await nav.closeCalendarIfSelected(42)

        #expect(nav.detailCalendarID == nil)
    }

    /// The caller reacts to a feed naming every calendar that left the active set, so closing
    /// has to be conditional. Unconditional, archiving one calendar would tear down the detail
    /// while the user was reading a different one.
    @Test("Closing some other calendar leaves the open one alone")
    @MainActor
    func closingAnotherCalendarChangesNothing() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))
        nav.goTo(.dayBatches)
        var left = 0
        nav.willLeaveCurrentCalendar = { left += 1 }

        await nav.closeCalendarIfSelected(7)

        #expect(nav.detailCalendarID == 42)
        #expect(nav.path.count == 1, "the pushed screen belongs to the calendar still open")
        #expect(left == 0, "and the calendar still open has not been left")
    }

    /// Closing with nothing open is the ordinary outcome of the very first archive a user does,
    /// so it must be inert rather than a crash or a stray notification.
    @Test("Closing when no calendar is open does nothing")
    @MainActor
    func closingWithNothingOpenIsInert() async {
        let nav = RootNavigation()
        var notified = 0
        nav.onCalendarChanged = { _ in notified += 1 }

        await nav.closeCalendarIfSelected(42)

        #expect(nav.detailCalendarID == nil)
        #expect(notified == 0, "there was no calendar to say had changed")
    }

    /// The stack belongs to the calendar being closed.
    ///
    /// Left in place, the detail shows the "select a calendar" placeholder *inside a navigation
    /// stack that still holds `.batchEditor`*, and that editor is built against a calendar that
    /// no longer exists — reading a store for an id the store can no longer write to.
    @Test("Closing the calendar clears its pushed screens")
    @MainActor
    func closingClearsThePushedStack() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))
        nav.goTo(.dayBatches)
        nav.goTo(.batchEditor)

        await nav.closeCalendarIfSelected(42)

        #expect(nav.path.isEmpty)
    }

    /// Leaving is not just a permission, it has a consequence: the calendar's multi-select
    /// session ends, and its batch goes if the user took every day back off. A close is a way of
    /// leaving that does not go through `switchCalendar`, so it has to run the same hook.
    @Test("Closing runs the leave hook, so the calendar's session cannot outlive it")
    @MainActor
    func closingRunsTheLeaveHook() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))
        var left = 0
        nav.willLeaveCurrentCalendar = { left += 1 }

        await nav.closeCalendarIfSelected(42)

        #expect(left == 1, "a cached store means an unended session comes back painted")
    }

    /// The hook reads `detailCalendarID` to find the store, so the ordering is observable rather
    /// than stylistic: run last, it would find nothing and end no session at all.
    @Test("The leave hook runs while the calendar is still the selected one")
    @MainActor
    func closingRunsTheLeaveHookBeforeClearingTheId() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))
        var seen: Int64?
        nav.willLeaveCurrentCalendar = { seen = nav.detailCalendarID }

        await nav.closeCalendarIfSelected(42)

        #expect(seen == 42)
    }

    /// No hook installed is the ordinary case for a close, and it must not stall.
    @Test("Closing without a leave hook still closes")
    @MainActor
    func closingWithoutALeaveHook() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))

        await nav.closeCalendarIfSelected(42)

        #expect(nav.detailCalendarID == nil)
    }

    /// The root injects the store this id names, and it is told from inside the mutation — so a
    /// close has to say `nil` too, or the root goes on injecting the store of a calendar that was
    /// just archived or deleted.
    @Test("Closing reports nil to the calendar-changed hook")
    @MainActor
    func closingNotifiesTheCalendarChangedHook() async {
        let nav = RootNavigation()
        var reported: [Int64?] = []
        nav.onCalendarChanged = { id in reported.append(id) }
        nav.goTo(.calendar(42, toRoot: false))
        #expect(reported == [42])

        await nav.closeCalendarIfSelected(42)

        #expect(reported == [42, nil], "and nil is reported *before* the id changes, like an opening")
    }

    /// Archiving the open calendar is not walking away from it, and the difference is a write.
    ///
    /// `switchCalendar` asks the guard because an unsaved edit must not be abandoned by leaving.
    /// Here the calendar is being archived or erased, so settling its write chain would mean
    /// writing to a row on its way out. Consulting the guard here would also mean an archive
    /// could be silently dropped because a write had failed — the user asked for the calendar to
    /// go, and it must go.
    @Test("Closing does not consult the write guard")
    @MainActor
    func closingDoesNotConsultTheWriteGuard() async {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: false))
        var asked = 0
        nav.canLeaveCurrentCalendar = {
            asked += 1
            return false
        }

        await nav.closeCalendarIfSelected(42)

        #expect(asked == 0)
        #expect(nav.detailCalendarID == nil, "a failed save is not a reason to keep a deleted calendar open")
    }

    // MARK: - Sheet Presentation Tests
    
    @Test("goTo addCalendar sets presentedSheet")
    @MainActor
    func goToAddCalendar() {
        let nav = RootNavigation()
        
        nav.goTo(.addCalendar)
        
        #expect(nav.presentedSheet == .addCalendar)
    }
    
    @Test("dismissSheet clears presentedSheet")
    @MainActor
    func dismissSheet() {
        let nav = RootNavigation()
        nav.goTo(.addCalendar)
        
        nav.dismissSheet()
        
        #expect(nav.presentedSheet == nil)
    }
    
    // MARK: - Path Management Tests
    
    @Test("calendar(toRoot: true) clears the navigation path")
    @MainActor
    func calendarToRootClearsPath() {
        let nav = RootNavigation()
        
        nav.goTo(.dayBatches)
        nav.goTo(.batchEditor)
        #expect(nav.path.count == 2)
        
        nav.goTo(.calendar(999, toRoot: true))
        
        #expect(nav.path.count == 0)
        #expect(nav.isAtRoot == true)
        #expect(nav.detailCalendarID == 999)
        #expect(nav.preferredCompactColumn == .detail)
    }
    
    @Test("isAtRoot is true initially")
    @MainActor
    func isAtRootInitially() {
        let nav = RootNavigation()
        #expect(nav.isAtRoot == true)
    }
    
    @Test("isAtRoot is false after push")
    @MainActor
    func isAtRootAfterPush() {
        let nav = RootNavigation()
        nav.goTo(.dayBatches)
        #expect(nav.isAtRoot == false)
    }
    
    @Test("isAtRoot is true after going to root via calendar(toRoot: true)")
    @MainActor
    func isAtRootAfterCalendarToRoot() {
        let nav = RootNavigation()
        nav.goTo(.dayBatches)
        nav.goTo(.calendar(999, toRoot: true))
        #expect(nav.isAtRoot == true)
    }

    // MARK: - pop()

    @Test("pop removes only the top of the stack")
    @MainActor
    func popRemovesOneLevel() {
        let nav = RootNavigation()
        nav.goTo(.dayBatches)
        nav.goTo(.batchEditor)

        nav.pop()

        #expect(nav.isAtRoot == false, "the day list is still on the stack")
        nav.pop()
        #expect(nav.isAtRoot == true)
    }

    @Test("pop on an empty stack does nothing rather than trapping")
    @MainActor
    func popOnEmptyStackIsSafe() {
        let nav = RootNavigation()
        #expect(nav.isAtRoot == true)
        nav.pop()
        nav.pop()
        #expect(nav.isAtRoot == true)
    }

    @Test("pop leaves the detail column alone")
    @MainActor
    func popDoesNotTouchTheDetailColumn() {
        let nav = RootNavigation()
        nav.goTo(.calendar(42, toRoot: true))
        nav.goTo(.dayBatches)

        nav.pop()

        #expect(nav.isAtRoot == true)
        #expect(
            nav.detailCalendarID == 42,
            "popping the pushed screen must not close the calendar we are inside"
        )
    }
    
    // MARK: - AppRoute NavigationStyle Tests
    
    @Test("AppRoute sidebar has open style")
    @MainActor
    func sidebarStyle() {
        #expect(AppRoute.sidebar(.calendarList).navigationStyle == .open)
        #expect(AppRoute.sidebar(.archived).navigationStyle == .open)
    }
    
    @Test("AppRoute calendar has open style")
    @MainActor
    func calendarStyle() {
        #expect(AppRoute.calendar(1, toRoot: false).navigationStyle == .open)
    }
    
    @Test("AppRoute dayBatches has push style")
    @MainActor
    func dayBatchesStyle() {
        #expect(AppRoute.dayBatches.navigationStyle == .push)
    }
    
    @Test("AppRoute batchEditor has push style")
    @MainActor
    func batchEditorStyle() {
        #expect(AppRoute.batchEditor.navigationStyle == .push)
    }

    @Test("AppRoute eventEditor has push style")
    @MainActor
    func eventEditorStyle() {
        #expect(AppRoute.eventEditor.navigationStyle == .push)
    }
    
    @Test("AppRoute addCalendar has present style")
    @MainActor
    func addCalendarStyle() {
        #expect(AppRoute.addCalendar.navigationStyle == .present)
    }
    
    // MARK: - AppRoute Hashable Tests
    
    @Test("AppRoute cases are hashable and comparable")
    @MainActor
    func appRouteHashable() {
        let route1 = AppRoute.calendar(1, toRoot: false)
        let route2 = AppRoute.calendar(1, toRoot: false)
        let route3 = AppRoute.calendar(2, toRoot: false)
        
        #expect(route1 == route2)
        #expect(route1 != route3)
        
        let sidebar1 = AppRoute.sidebar(.calendarList)
        let sidebar2 = AppRoute.sidebar(.calendarList)
        let sidebar3 = AppRoute.sidebar(.archived)
        
        #expect(sidebar1 == sidebar2)
        #expect(sidebar1 != sidebar3)
    }
}