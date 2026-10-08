
import SwiftUI
import AppNavigation
import DSKit
import SettingsFeature
import SingleCalendarFeature

struct RootView: View {
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()
    @Environment(PCAppSession.self) private var session
    /// The app's settings, and the reason this view renders the theme and the vibe.
    ///
    /// Read during `body`, which is what makes it work: the store is `@Observable`, so accessing
    /// `theme` registers this body with the observation system and changing the setting from the
    /// settings screen re-renders this view. That is the whole reason the port is observable and the
    /// reason `@AppStorage` is gone — a stateless `UserDefaults` forwarder has nothing to subscribe
    /// to, so a read from one would be a snapshot of launch-time values that nothing ever invalidates.
    ///
    /// `theme` and `vibeId` are the decoded forms supplied by `SettingsPersisting+Decoded`, so this
    /// view never sees a stored string and never has to decide what an unrecognised one means.
    @Environment(\.settingsPersisting) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var bindableNavigation = navigation
        let compactBinding = Binding<NavigationSplitViewColumn>(
            get: { horizontalSizeClass == .compact ? navigation.preferredCompactColumn : .sidebar },
            set: { navigation.preferredCompactColumn = $0 }
        )
        let theme = settings?.theme ?? .system
        let vibe = PCVibe.all.first { $0.id == settings?.vibeId } ?? .default
        if settings == nil {
            // The app root injects unconditionally, so a `nil` here is a wiring bug rather than a
            // state to design for, and the two reads above have already fallen back to the values
            // this app would ship with.
            //
            // Falling back is acceptable *here* and not in `SettingsView`, and the difference is what
            // the fallback degrades: wrong colours for a cosmetic setting is a survivable release
            // build, where `SettingsView`'s equivalent is an endless "Loading" that hides the cause.
            // The assertion is the report — it fires in debug, which is where this would be found.
            assertionFailure("RootView presented without \\.settingsPersisting in the environment.")
        }
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
            //
            // `0` for "no calendar", which is the state the session already documents for before
            // the first one is opened: `perform` refuses to write against it, so the store the
            // root injects then is inert rather than dangerous. Closing a calendar has to say so
            // for the same reason — otherwise the root keeps injecting the store of a calendar
            // that was just archived or deleted.
            //
            // The same hook is where the selection is remembered, because it is the only place
            // that hears about a change from inside the mutation — including the `nil` that a
            // close reports, which is what stops a calendar that has been archived or deleted
            // from coming back on the next launch.
            navigation.onCalendarChanged = { id in
                session.currentCalendarID = id ?? 0
                session.rememberSelectedCalendar(id)
            }

            // Reopen whatever was on screen when the app was last used.
            //
            // **After** the three hooks above, deliberately. The switch below runs `goTo`, which
            // notifies `onCalendarChanged`; if the hook were not installed yet, `currentCalendarID`
            // would stay `0` and the detail would be built against the inert store — one render of
            // the symptom `RootNavigation` calls a day list that opens empty.
            //
            // And only when nothing has been selected in the meantime. Deciding what to restore is
            // an `await` over storage, and the list is on screen behind it: a user who tapped a
            // calendar while that was in flight asked for *that* calendar, and restoring over the
            // top of it would answer a question they had already answered.
            if navigation.detailCalendarID == nil,
               let id = await session.selectedCalendarToRestore()
            {
                await navigation.switchCalendar(to: id)
            }
        }
        .onChange(of: navigation.detailCalendarID) { _, id in
            // A backstop, not the mechanism. The real update is `onCalendarChanged`, which
            // `RootNavigation` calls *before* it changes the id — an observer here would run a
            // frame late, and this value chooses which store the app root injects. Kept so a
            // calendar selected by any route that bypasses `goTo` still reaches the session.
            //
            // `nil` is not handled here on purpose: a close notifies through
            // `onCalendarChanged(nil)` in the same mutation that clears the id, so the store has
            // already been swapped by the time this fires. Writing `0` from here as well would be
            // harmless today and would paper over a future route that clears the id without
            // notifying — which is the failure this backstop exists to catch, not to hide.
            //
            // The selection is not remembered from here either, for the same reason: an observer
            // is a frame late, and the remembered value is read on the *next* launch rather than
            // rendered now, so a frame of staleness would not show — but it would still be the
            // wrong hook, and `onCalendarChanged` already carries both.
            if let id {
                session.currentCalendarID = id
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .pcVibe(vibe)
        .onOpenURL { url in
            // A link from outside: `pincalapp://calendars/4`, or the query-shaped
            // `pincalapp://calendars?calendarid=4`. Anything this app does not recognise parses to
            // nothing and is ignored — a link can arrive from a web page, and one that is not
            // addressed to us is not a thing to report to the user.
            //
            // Routed through `switchCalendar` rather than `goTo`, so the write guard is consulted
            // and the calendar being left ends its multi-select session. A link arriving while
            // the user is mid-edit is a switch like any other, and must be refused by the same
            // rule that refuses a tap on another row.
            guard let link = CalendarDeepLink(url: url) else { return }
            Task {
                if await session.calendarExists(link.calendarID) {
                    await navigation.switchCalendar(to: link.calendarID)
                } else {
                    // The link named a calendar that is not there. Say so *and* move: an alert on
                    // its own would be dismissed over whatever calendar happened to be open,
                    // which is not the screen the link was asking about.
                    await navigation.reportDeepLinkFailure(.noSuchCalendar(id: link.calendarID))
                }
            }
        }
        // Built here rather than in `AppNavigation`, which holds no strings: the navigation says
        // *what* went wrong and this decides what to say about it.
        .pcAlert(
            Binding(
                get: { bindableNavigation.deepLinkFailure.map { failure in
                    // Exhaustive on purpose: a second kind of link failure gets its own words
                    // here rather than silently reusing this one's.
                    switch failure {
                    case .noSuchCalendar:
                        PCAlertContent(
                            title: String(localized: "Calendar not found"),
                            message: String(localized: "That calendar does not exist"),
                            dismiss: String(localized: "OK")
                        )
                    }
                } },
                set: {
                    if $0 == nil {
                        bindableNavigation.deepLinkFailure = nil
                    }
                }
            )
        )
    }
}
