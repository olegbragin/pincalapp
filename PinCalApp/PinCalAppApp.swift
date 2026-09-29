import SwiftUI
import CorePersistence
import CoreDomain
import DSKit
import SingleCalendarFeature
import CalendarListFeature

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
    /// The batch-assembly store (Stage 6). Built here and injected, but nothing reads it
    /// yet — the view models are rewired onto it in Stage 8, and the old
    /// `PCEventsSelectionManager` stays live until then. Constructing it now is what
    /// proves the composition root can actually satisfy it from the `CalendarPersisting`
    /// port alone, without the feature layer naming `CorePersistence`.
    private let eventSelection: PCEventSelectionManager

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
        // The store keeps its own `dataProvider` inside its state rather than taking one
        // here, because the reducer needs it and the state has to be `Equatable`. Handing
        // it the session's instance is what keeps the store and the session agreeing about
        // which day a timestamp names.
        self.eventSelection = PCEventSelectionManager(
            initialState: PCEventSelectionState(dataProvider: dataProvider),
            persistence: store,
            columnCountResolver: columnCountResolver
        )
        let daySelectionManager = PCCalendarDaySelectionManager()
        let eventsSelectionManager = PCEventsSelectionManager(
            cache: cache,
            dataProvider: dataProvider,
            daySelectionManager: daySelectionManager,
            columnCountResolver: columnCountResolver
        )
        _session = State(
            initialValue: PCCalendarSession(
                persistence: store,
                dataProvider: dataProvider,
                columnCountResolver: columnCountResolver,
                daySelectionManager: daySelectionManager,
                eventsSelectionManager: eventsSelectionManager
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.calendarCache, cache)
                .environment(\.calendarManaging, managing)
                .environment(eventSelection)
        }
    }
}
