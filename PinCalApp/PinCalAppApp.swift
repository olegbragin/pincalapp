
import SwiftUI
import CalendarListFeature
import CoreDomain
import CorePersistence
import DSKit
import SettingsFeature
import SingleCalendarFeature

@main
struct PinCalAppApp: App {
    @State private var session: PCAppSession
    /// Owned here and injected through the `\.calendarCache` key. It stays out of
    /// `PCAppSession` deliberately: the session hands out the domain port, and only
    /// the two places that genuinely need storage still get the cache. It cannot be
    /// injected as a SwiftUI environment *object* — that requires `Observable`, and
    /// `@Observable` cannot be applied to an actor.
    private let cache: CalendarCache
    /// The same `CalendarStore` the session was built with, re-typed as the calendar
    /// list's port. One instance, so the list and the session share one cache and one
    /// change feed; injecting a second store would mean two independent subscriptions to
    /// the same actor.
    private let managing: any CalendarManaging
    /// The app's settings, held as the port `SettingsFeature` declares rather than as the
    /// `UserDefaults` store it happens to be. Owned here so the injection is a stored value —
    /// rebuilding it in `body` would hand the environment a different instance on every re-render.
    ///
    /// A *port*, and the only settings dependency the app holds. `SettingsView` builds its own
    /// model over it, and `RootView` reads the two appearance settings by key through
    /// `@AppStorage`; neither needs a model handed down from here, and the model is `internal` to
    /// `SettingsFeature` so that stays true.
    private let settingsStore: any SettingsPersisting

    init() {
        #if os(iOS)
            UITableView.appearance().backgroundColor = .clear
            UITableViewCell.appearance().backgroundColor = .clear
        #endif

        // The composition root. Everything the session holds is built here, in the
        // one place that knows how the pieces fit together.
        //
        // `CorePersistence` and `CoreDomain` do not depend on each other, so
        // `CalendarStore` — the one type that carries a cache and satisfies the domain
        // ports — is built here and handed to the session, rather than the session
        // building it for itself.
        let cache = CalendarCache(repository: CalendarRepositoryFactory.makeDefault())
        self.cache = cache
        let store = CalendarStore(cache: cache)
        self.managing = store
        self.settingsStore = PCAppSession.makeSettingsStore()
        let dataProvider = PCCalendarDataProvider()
        let columnCountResolver = PCAppSession.makeColumnCountResolver()
        // One batch-assembly store per calendar, built on first use by the session.
        //
        // There was a single store here, injected into the environment for the whole app, and
        // that made the first calendar opened pin the store's `calendarID` for the life of the
        // process — so a second calendar's batches were rejected on sync and its taps were
        // written into the first calendar's row by a destructive save. `PCAppSession` owns
        // the cache and says why.
        //
        // The day-selection manager is per store and must be: the store writes `selectedDays`
        // on it and installs a tap listener, so sharing one across calendars would let the
        // editor's selection mode and tap handler leak onto the screen behind. See
        // `PCEventSelectionManager.daySelectionManager`.
        let makeEventSelection: @MainActor (Int64) -> PCEventSelectionManager = { _ in
            PCEventSelectionManager(
                initialState: PCEventSelectionState(dataProvider: dataProvider),
                persistence: store,
                daySelectionManager: PCCalendarDaySelectionManager(),
                columnCountResolver: columnCountResolver,
                nameAutosaveDelay: PCAppSession.makeNameAutosaveDelay()
            )
        }
        _session = State(
            initialValue: PCAppSession(
                persistence: store,
                // The same object, under the wider port. One store means one cache and one
                // change feed; injecting a second would mean two subscriptions to the same
                // actor, and the two subscribers would not agree about anything.
                managing: store,
                // The same adapter the settings holder was built over, so every setting the app
                // reads and writes goes through one place.
                settings: settingsStore,
                makeEventSelection: makeEventSelection,
                dataProvider: dataProvider,
                columnCountResolver: columnCountResolver
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.calendarCache, cache)
                .environment(\.calendarManaging, managing)
                .environment(\.settingsPersisting, settingsStore)
                // No localization injection, because there is nothing to inject: every string in
                // the app is resolved by `String(localized:)` or a SwiftUI `LocalizedStringKey`,
                // both of which read the main bundle — which is where `Localizable.xcstrings`
                // lives. A feature has no localization port to satisfy and no key enum to map, so
                // there is nothing for a composition root to wire and nothing it could get wrong.
                // The current calendar's store, injected at the root.
                //
                // Still app-wide — not because sharing is right, but because a
                // `navigationDestination`'s content does not reliably inherit an environment
                // applied below the `NavigationStack`, and every pushed editor reads the store
                // from `@Environment`. Injecting per calendar *here* rather than below the stack
                // is what makes it per calendar without that trap; see
                // `PCAppSession.currentEventSelection`.
                //
                // `session` is `@State` over an `@Observable`, so this body re-runs when
                // `currentCalendarID` changes — which is what swaps the injected store.
                .environment(session.currentEventSelection)
        }
    }
}
