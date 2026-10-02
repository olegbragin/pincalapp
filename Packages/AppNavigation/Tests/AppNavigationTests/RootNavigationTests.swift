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