import SwiftUI
import CorePersistence
import DSKit
import AppNavigation
import SingleCalendarFeature

/// App-root session object. Owns the shared batch-editing managers, which are
/// injected into `SingleCalendarModel` and the batch views so all three models
/// communicate through them.
struct PCCalendarSession {
    let eventsSelectionManager: PCEventsSelectionManager
    let daySelectionManager: PCCalendarDaySelectionManager

    init() {
        let daySelectionManager = PCCalendarDaySelectionManager()
        self.daySelectionManager = daySelectionManager
        self.eventsSelectionManager = PCEventsSelectionManager(daySelectionManager: daySelectionManager)
    }
}

struct RootDetailView: View {
    @Environment(RootNavigation.self) private var navigation
    let cache: CalendarCache
    @State private var session = PCCalendarSession()

    var body: some View {
        @Bindable var bindableNavigation = navigation
        NavigationStack(path: $bindableNavigation.path) {
            ZStack {
                Rectangle()
                    .fill(Color.dsKit.colorBackgroundMain)
                    .ignoresSafeArea()
                if let id = navigation.detailCalendarID {
                    CalendarDetailView(
                        calendarId: id,
                        cache: cache,
                        eventsSelectionManager: session.eventsSelectionManager,
                        daySelectionManager: session.daySelectionManager
                    )
                } else {
                    ContentUnavailableView(
                        "Select a calendar",
                        systemImage: "calendar",
                        description: Text("Choose a calendar from the list")
                    )
                }
            }
        }
        .background(Color.dsKit.colorBackgroundMain)
    }
}
