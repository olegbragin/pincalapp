import Testing
import Foundation
@testable import AppNavigation

@Suite("RootNavigation Tests")
struct RootNavigationTests {
    
    // MARK: - Initial State Tests
    
    @Test("Initial state has calendarList selected and empty path")
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
    func goToSidebarCalendarList() {
        let nav = RootNavigation()
        nav.goTo(.sidebar(.calendarList))
        
        #expect(nav.selectedSidebarCategory == .calendarList)
        #expect(nav.detailCalendarID == nil)
    }
    
    @Test("goTo sidebar archived sets category and clears detail")
    func goToSidebarArchived() {
        let nav = RootNavigation()
        // First set a detail calendar
        nav.goTo(.calendar(42, toRoot: false))
        #expect(nav.detailCalendarID == 42)
        
        // Now switch to archived
        nav.goTo(.sidebar(.archived))
        
        #expect(nav.selectedSidebarCategory == .archived)
        #expect(nav.detailCalendarID == nil)
    }
    
    // MARK: - Calendar Detail Tests
    
    @Test("goTo calendar sets detailCalendarID and preferredCompactColumn")
    func goToCalendar() {
        let nav = RootNavigation()
        nav.goTo(.calendar(123, toRoot: false))
        
        #expect(nav.detailCalendarID == 123)
        #expect(nav.preferredCompactColumn == .detail)
        #expect(nav.presentedSheet == nil)
    }
    
    @Test("goTo calendar clears presented sheet")
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
    func goToDayBatches() {
        let nav = RootNavigation()
        _ = Date()
        
        nav.goTo(.dayBatches(Date()))
        
        #expect(nav.path.count == 1)
    }
    
    @Test("goTo batchEditor newDay appends to path")
    func goToBatchEditorNewDay() {
        let nav = RootNavigation()
        _ = Date()
        
        nav.goTo(.batchEditor(.newDay(Date())))
        
        #expect(nav.path.count == 1)
    }
    
    @Test("goTo batchEditor existingBatch appends to path")
    func goToBatchEditorExistingBatch() {
        let nav = RootNavigation()
        
        nav.goTo(.batchEditor(.existingBatch(789)))
        
        #expect(nav.path.count == 1)
    }
    
    @Test("Multiple push routes accumulate in path")
    func multiplePushRoutes() {
        let nav = RootNavigation()
        
        nav.goTo(.dayBatches(Date()))
        nav.goTo(.batchEditor(.newDay(Date())))
        
        #expect(nav.path.count == 2)
    }
    
    // MARK: - Sheet Presentation Tests
    
    @Test("goTo addCalendar sets presentedSheet")
    func goToAddCalendar() {
        let nav = RootNavigation()
        
        nav.goTo(.addCalendar)
        
        #expect(nav.presentedSheet == .addCalendar)
    }
    
    @Test("dismissSheet clears presentedSheet")
    func dismissSheet() {
        let nav = RootNavigation()
        nav.goTo(.addCalendar)
        
        nav.dismissSheet()
        
        #expect(nav.presentedSheet == nil)
    }
    
    // MARK: - Path Management Tests
    
    @Test("calendar(toRoot: true) clears the navigation path")
    func calendarToRootClearsPath() {
        let nav = RootNavigation()
        
        nav.goTo(.dayBatches(Date()))
        nav.goTo(.batchEditor(.newDay(Date())))
        #expect(nav.path.count == 2)
        
        nav.goTo(.calendar(999, toRoot: true))
        
        #expect(nav.path.count == 0)
        #expect(nav.isAtRoot == true)
        #expect(nav.detailCalendarID == 999)
        #expect(nav.preferredCompactColumn == .detail)
    }
    
    @Test("isAtRoot is true initially")
    func isAtRootInitially() {
        let nav = RootNavigation()
        #expect(nav.isAtRoot == true)
    }
    
    @Test("isAtRoot is false after push")
    func isAtRootAfterPush() {
        let nav = RootNavigation()
        nav.goTo(.dayBatches(Date()))
        #expect(nav.isAtRoot == false)
    }
    
    @Test("isAtRoot is true after going to root via calendar(toRoot: true)")
    func isAtRootAfterCalendarToRoot() {
        let nav = RootNavigation()
        nav.goTo(.dayBatches(Date()))
        nav.goTo(.calendar(999, toRoot: true))
        #expect(nav.isAtRoot == true)
    }
    
    // MARK: - AppRoute NavigationStyle Tests
    
    @Test("AppRoute sidebar has open style")
    func sidebarStyle() {
        #expect(AppRoute.sidebar(.calendarList).navigationStyle == .open)
        #expect(AppRoute.sidebar(.archived).navigationStyle == .open)
    }
    
    @Test("AppRoute calendar has open style")
    func calendarStyle() {
        #expect(AppRoute.calendar(1, toRoot: false).navigationStyle == .open)
    }
    
    @Test("AppRoute dayBatches has push style")
    func dayBatchesStyle() {
        #expect(AppRoute.dayBatches(Date()).navigationStyle == .push)
    }
    
    @Test("AppRoute batchEditor has push style")
    func batchEditorStyle() {
        #expect(AppRoute.batchEditor(.newDay(Date())).navigationStyle == .push)
        #expect(AppRoute.batchEditor(.existingBatch(1)).navigationStyle == .push)
    }
    
    @Test("AppRoute addCalendar has present style")
    func addCalendarStyle() {
        #expect(AppRoute.addCalendar.navigationStyle == .present)
    }
    
    // MARK: - AppRoute Hashable Tests
    
    @Test("AppRoute cases are hashable and comparable")
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