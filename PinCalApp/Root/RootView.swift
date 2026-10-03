import SwiftUI
import DSKit
import SettingsFeature
import AppNavigation
import SingleCalendarFeature

struct RootView: View {
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()
    @Environment(PCCalendarSession.self) private var session
    @AppStorage(SettingsViewModel.themeKey) private var theme: AppTheme = .system
    @AppStorage(SettingsViewModel.vibeKey) private var vibeId: String = PCVibe.default.id
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var bindableNavigation = navigation
        let compactBinding = Binding<NavigationSplitViewColumn>(
            get: { horizontalSizeClass == .compact ? navigation.preferredCompactColumn : .sidebar },
            set: { navigation.preferredCompactColumn = $0 }
        )
        let vibe = PCVibe.all.first { $0.id == vibeId } ?? .default
        return NavigationSplitView(preferredCompactColumn: compactBinding) {
            RootSidebarView()
        } content: {
            RootContentView()
        } detail: {
            RootDetailView()
        }
        .environment(navigation)
        .environment(keyboardState)
        .task {
            // Let navigation ask the store before it abandons a calendar, and tell it when it
            // has.
            //
            // Installed here, where both the navigation object and the session are in scope, so
            // neither closure can outlive or miss the navigation they act on. `.task` rather
            // than `onAppear` because they are async and must be cancellable if the view is torn
            // down mid-switch.
            //
            // Both resolve the store from the calendar being left, not from a single instance:
            // the store is per calendar, so there is no "the" store to ask.
            navigation.canLeaveCurrentCalendar = { [session, navigation] in
                guard let id = navigation.detailCalendarID else { return true }
                return await session.eventSelection(for: id).flushBeforeLeavingCalendar()
            }
            navigation.willLeaveCurrentCalendar = { [session, navigation] in
                guard let id = navigation.detailCalendarID else { return }
                session.endSession(for: id)
            }
            // The app root injects the current calendar's store, so the session has to be told
            // which calendar that is. Set from the navigation mutation rather than from an
            // `onChange` here, or the root would inject the previous calendar's store for one
            // render — long enough for the calendar detail to be built against a store no view
            // is reading.
            navigation.onCalendarChanged = { id in
                session.currentCalendarID = id
            }
        }
        .onChange(of: navigation.detailCalendarID) { _, id in
            // A backstop, not the mechanism. The real update is `onCalendarChanged`, which
            // `RootNavigation` calls *before* it changes the id — an observer here would run a
            // frame late, and this value chooses which store the app root injects. Kept so a
            // calendar selected by any route that bypasses `goTo` still reaches the session.
            if let id { session.currentCalendarID = id }
        }
        .preferredColorScheme(theme.colorScheme)
        .pcVibe(vibe)
    }
}
