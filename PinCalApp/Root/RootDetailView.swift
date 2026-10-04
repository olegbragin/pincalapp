
import SwiftUI
import AppNavigation
import DSKit

struct RootDetailView: View {
    @Environment(RootNavigation.self) private var navigation
    @Environment(\.pcVibe) private var vibe

    /// Does not inject the store. `PinCalAppApp` does, app-wide, with the current calendar's
    /// store — see the note there. Injecting here instead would be tidier-looking and wrong: a
    /// `navigationDestination`'s content is rendered in the `NavigationStack`'s context and does
    /// not inherit an environment applied below it, so every pushed editor would trap on a
    /// missing required environment value.
    var body: some View {
        @Bindable var bindableNavigation = navigation
        NavigationStack(path: $bindableNavigation.path) {
            ZStack {
                Rectangle()
                    .fill(vibe.color(for: .backgroundMain))
                    .ignoresSafeArea()
                if let id = navigation.detailCalendarID {
                    CalendarDetailView(calendarId: id)
                } else {
                    ContentUnavailableView(
                        "Select a calendar",
                        systemImage: "calendar",
                        description: Text("Choose a calendar from the list")
                    )
                }
            }
        }
        .background(vibe.color(for: .backgroundMain))
    }
}
