import SwiftUI
import DSKit
import SettingsFeature
import AppNavigation

struct RootView: View {
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()
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
        .preferredColorScheme(theme.colorScheme)
        .pcVibe(vibe)
    }
}
