import SwiftUI
import DSKit
import SettingsFeature
import AppNavigation
import SingleCalendarFeature

struct RootView: View {
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()
    @Environment(PCEventSelectionManager.self) private var eventSelection
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
            // Let navigation ask the store before it abandons a calendar.
            //
            // Installed here, where both the navigation object and the store are in scope, so
            // the guard cannot outlive or miss the navigation it guards. `.task` rather than
            // `onAppear` because the closure is async and must be cancellable if the view is
            // torn down mid-switch.
            navigation.canLeaveCurrentCalendar = { [eventSelection] in
                await eventSelection.flushBeforeLeavingCalendar()
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .pcVibe(vibe)
    }
}
