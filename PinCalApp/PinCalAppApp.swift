
import SwiftUI
import CalendarListFeature
import CoreDomain
import CorePersistence
import DSKit
import SingleCalendarFeature

@main
struct PinCalAppApp: App {
    @State private var session: PCCalendarSession
    /// Owned here and injected through the `\.calendarCache` key. It stays out of
    /// `PCCalendarSession` deliberately: the session hands out the domain port, and only
    /// the two places that genuinely need storage still get the cache. It cannot be
    /// injected as a SwiftUI environment *object* — that requires `Observable`, and
    /// `@Observable` cannot be applied to an actor.
    private let cache: CalendarCache
    /// The same `CalendarStore` the session was built with, re-typed as the calendar
    /// list's port. One instance, so the list and the session share one cache and one
    /// change feed; injecting a second store would mean two independent subscriptions to
    /// the same actor.
    private let managing: any CalendarManaging

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
        let dataProvider = PCCalendarDataProvider()
        let columnCountResolver = PCCalendarSession.makeColumnCountResolver()
        // One batch-assembly store per calendar, built on first use by the session.
        //
        // There was a single store here, injected into the environment for the whole app, and
        // that made the first calendar opened pin the store's `calendarID` for the life of the
        // process — so a second calendar's batches were rejected on sync and its taps were
        // written into the first calendar's row by a destructive save. `PCCalendarSession` owns
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
                nameAutosaveDelay: PCCalendarSession.makeNameAutosaveDelay()
            )
        }
        _session = State(
            initialValue: PCCalendarSession(
                persistence: store,
                // The same object, under the wider port. One store means one cache and one
                // change feed; injecting a second would mean two subscriptions to the same
                // actor, and the two subscribers would not agree about anything.
                managing: store,
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
                // The current calendar's store, injected at the root.
                //
                // Still app-wide — not because sharing is right, but because a
                // `navigationDestination`'s content does not reliably inherit an environment
                // applied below the `NavigationStack`, and every pushed editor reads the store
                // from `@Environment`. Injecting per calendar *here* rather than below the stack
                // is what makes it per calendar without that trap; see
                // `PCCalendarSession.currentEventSelection`.
                //
                // `session` is `@State` over an `@Observable`, so this body re-runs when
                // `currentCalendarID` changes — which is what swaps the injected store.
                .environment(session.currentEventSelection)
        }
    }
}
