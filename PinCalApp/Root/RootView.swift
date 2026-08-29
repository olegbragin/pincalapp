import SwiftUI
import CoreDomain
import CorePersistence
import DSKit
import CalendarListFeature
import AppNavigation

struct RootView: View {
    let cache: CalendarCache
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var bindableNavigation = navigation
        let compactBinding = Binding<NavigationSplitViewColumn>(
            get: { horizontalSizeClass == .compact ? navigation.preferredCompactColumn : .sidebar },
            set: { navigation.preferredCompactColumn = $0 }
        )
        return NavigationSplitView(preferredCompactColumn: compactBinding) {
            RootSidebarView()
        } content: {
            RootContentView(cache: cache)
        } detail: {
            RootDetailView(cache: cache)
        }
        .environment(navigation)
        .environment(keyboardState)
    }
}
