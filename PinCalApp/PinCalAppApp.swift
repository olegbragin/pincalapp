
import os
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
    /// Where failures go.
    ///
    /// Held but **not yet injected** — nothing calls it yet. Recording is the next piece of work,
    /// and the reason this is plumbed now is that the reporter has to be built from the same
    /// `Store` as the repository, which is decided here and nowhere else.
    private let errorReporter: any PCErrorReporting
    /// The same reporter, wrapped for the environment. See `PCErrorRecorder`.
    private let errorRecorder: PCErrorRecorder

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
        // Opening the database can fail — a full disk, a locked container, a corrupt store. It used
        // to be `try!` two layers down, which trapped here in all but name.
        //
        // It is now caught, and the choice made here is deliberate: **stop, and say so.**
        //
        // The alternative was to fall back to an in-memory store and carry on. That was rejected
        // because it converts a loud failure into the exact thing this codebase has spent this
        // whole change removing: an app that looks like it is working, while silently persisting
        // nothing. Every event added would be lost on relaunch, and nothing would say why.
        //
        // An `App.init` cannot present a recovery UI, so an honest trap with the reason is the
        // most this layer can do. Doing better means failing *after* launch, behind a screen —
        // which is the right shape and is not this change.
        //
        // The reporter rides along here rather than opening a database of its own, which is why
        // the factory returns a `Stack`: ObjectBox permits one `Store` per directory, so the two
        // have to be built from the same one.
        let repository: any CalendarRepository
        let errorReporter: any PCErrorReporting
        do {
            let stack = try CalendarRepositoryFactory.makeDefault()
            repository = stack.repository
            errorReporter = stack.reporter
        } catch {
            // Logged before trapping: `fatalError` output reaches the device console but not
            // anywhere a person reads it.
            Logger(subsystem: "com.crucialsoftware.PinCalApp", category: "app")
                .fault("Could not open the calendar database: \(String(describing: error), privacy: .public)")
            fatalError("Could not open the calendar database: \(String(describing: error))")
        }

        let cache = CalendarCache(repository: repository)
        self.cache = cache
        let store = CalendarStore(cache: cache)
        self.managing = store
        self.errorReporter = errorReporter
        // Injected once, here, rather than constructed at each site: a second recorder would mean
        // a second thing that looks like the reporter and may not be it.
        self.errorRecorder = PCErrorRecorder(reporter: errorReporter)
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
                columnCountResolver: columnCountResolver
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
                .environment(\.pcErrorRecorder, errorRecorder)
                .environment(\.pcErrorReporting, errorReporter)
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
