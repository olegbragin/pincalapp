//
//  PCAppSession.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import Foundation
import Observation
import CoreDomain
import CorePersistence
import DSKit
import SettingsFeature
import SingleCalendarFeature

/// App-root session object. Bundles the app-wide dependencies that are shared
/// across calendars and injected into the models from `@Environment` through the
/// views, so they no longer have to be threaded through every initializer.
///
/// It owns the batch-assembly stores, one **per calendar**, which every screen in the flow reads
/// and dispatches through. This is the only file in the app that names both `CalendarCache` and
/// `PCEventSelectionManager`: the former is storage, the latter is the domain-facing feature, and
/// the only place the two are allowed to meet is the composition root.
///
/// ## Why one store per calendar, and not one for the app
///
/// There was one, and it was wrong in two ways that only showed up on a second calendar.
///
/// `state.calendarID` is written in exactly one place — `syncCalendar` — behind a guard that
/// accepts a calendar only if it matches the id already held or that id is still `0`. With one
/// store for the process, the first calendar ever opened pinned it forever: switching to a second
/// calendar had its `syncCalendar` **rejected**, so the registry kept the first calendar's rows,
/// the second calendar's grid painted the first calendar's markers, `hasEvents(on:)` answered
/// from the wrong rows, and every write still targeted the pinned id. `saveCalendar` is
/// destructive delete-then-insert, so a tap in the second calendar wrote into the first
/// calendar's row. That is data loss, and nothing in the app noticed.
///
/// And a multi-select session is store state, so it survived the switch too — the painted days
/// and the colour picker reappeared on a calendar the session knew nothing about. `switchCalendar`
/// only ever flushed writes, `isAtRoot` is `path.isEmpty` and the switch's `popToRoot()` acts on
/// an already-empty path (so `onChange(of: navigation.isAtRoot)` cannot fire), and the only
/// thing that reset a session was the `.id(calendarId)` teardown in `CalendarDetailView` — which
/// does not run on iPad when the detail column never loads. A leaked session is not merely
/// untidy: `withoutRowsOutgrown` drops the session's outgrown rows from the registry, and the
/// next tap's write is destructive, so coming back to that calendar deleted rows for real.
///
/// One store per calendar removes both by construction: a store only ever holds one calendar's
/// rows, so the guard in `syncCalendar` cannot reject anything, and a session cannot outlive the
/// calendar it belongs to.
///
/// The stores are **cached, not rebuilt**, so returning to a calendar restores its state —
/// including its staged edit — instead of silently discarding work. `endSession(for:)` is the
/// hook that makes a cache safe rather than a leak: it is called when a calendar is left, so
/// nothing is left holding a session the user can no longer see or end.
///
/// It builds nothing. Every collaborator arrives through `init` — the port over the
/// calendar store, the data provider, the column-count resolver, and the factory for a calendar's
/// store — so a test can hand it whatever it needs. Its job is to hold them and hand them to the
/// rest of the app, not to decide what they are.
///
/// It holds no `CalendarCache`. The storage vocabulary stops here: consumers that need the
/// domain view ask for `persistence`, and the one consumer that genuinely needed the
/// cache — `SingleCalendarModel`, for the calendar's metadata feed — now asks
/// `managing` for it instead and took `import CorePersistence` with it in Stage 9.
///
/// The storage/domain boundary is wired one level up, in `PinCalAppApp`, which is the
/// composition root. `CorePersistence` and `CoreDomain` do not depend on each other,
/// so the `CalendarStore` that joins them is constructed at the call site and handed in
/// here as `any CalendarPersisting`.
@MainActor
@Observable
final class PCAppSession {
    /// The domain-facing view of the calendar store. The batch pipeline is handed this
    /// and nothing else, so it cannot reach the `CalendarDataSource` DTOs.
    let persistence: any CalendarPersisting
    /// Calendar *management*: the metadata change feed, alongside the list's own
    /// load/create/archive operations. `SingleCalendarModel` follows this calendar's name,
    /// year, archived flag and column count, which are not batch state — so they do not
    /// belong on the batch port — and are not storage, so the model does not need a cache.
    /// This is what let `SingleCalendarFeature` drop `CorePersistence` in Stage 9.
    let managing: any CalendarManaging
    let dataProvider: PCCalendarDataProvider
    let columnCountResolver: (Int) -> Int

    /// The app's settings, as `SettingsFeature` sees them.
    ///
    /// The *same* instance the app root injects and builds the settings holder from, rather than a
    /// second `SettingsStore` over the same `UserDefaults.standard`. It would work either way —
    /// the adapter is a stateless forward — but two adapters over one store is the arrangement this
    /// file already argues against for the calendar store, and there is no reason to invite it here.
    private let settings: any SettingsPersisting

    /// Builds a store for one calendar. A closure rather than the collaborators themselves so
    /// this type still does not decide what a store is made of — the composition root supplies
    /// the wiring, and a test can supply a store over its own port.
    private let makeEventSelection: @MainActor (Int64) -> PCEventSelectionManager

    /// One store per calendar, created on first use.
    ///
    /// `@ObservationIgnored` because the dictionary is a cache, not view state: the stores
    /// inside it are individually `@Observable` and views observe those directly through
    /// `@Environment`, so observing the container would only add invalidations nobody wants.
    @ObservationIgnored
    private var eventSelections: [Int64: PCEventSelectionManager] = [:]

    init(
        persistence: any CalendarPersisting,
        managing: any CalendarManaging,
        settings: any SettingsPersisting,
        makeEventSelection: @escaping @MainActor (Int64) -> PCEventSelectionManager,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        columnCountResolver: @escaping (Int) -> Int = PCAppSession.makeColumnCountResolver()
    ) {
        self.persistence = persistence
        self.managing = managing
        self.settings = settings
        self.makeEventSelection = makeEventSelection
        self.dataProvider = dataProvider
        self.columnCountResolver = columnCountResolver
    }

    /// The calendar whose store is currently on screen.
    ///
    /// Read by `PinCalAppApp` to inject *that calendar's* store app-wide, and kept here because
    /// the app root has no other way to know which calendar the navigation is showing —
    /// `RootNavigation` owns that, and the root does not.
    ///
    /// Defaults to `0`, which is not a real calendar id: `perform` already refuses to write
    /// against `0`, so the store that exists before any calendar is opened is inert rather than
    /// dangerous. It is still created, because `@Environment` demands a value and there is no
    /// optional form to inject.
    ///
    /// Observable, and the only mutable property here, precisely so the root's `body` re-runs
    /// when it changes — that re-run is what swaps the injected store.
    var currentCalendarID: Int64 = 0

    /// The store for `calendarID`, built on first use and cached after that.
    ///
    /// Cached so that leaving and returning to a calendar restores its staged edit rather than
    /// dropping it. A store is cheap — a state value, a year model, a write chain — and the
    /// number of calendars a person has is small, so an unbounded cache is not worth bounding.
    func eventSelection(for calendarID: Int64) -> PCEventSelectionManager {
        if let existing = eventSelections[calendarID] {
            return existing
        }
        let store = makeEventSelection(calendarID)
        eventSelections[calendarID] = store
        return store
    }

    /// The store for `currentCalendarID` — the one to inject at the app root.
    ///
    /// Every screen that reads the store does so from `@Environment`, and a `navigationDestination`'s
    /// content does not reliably inherit an environment applied below the `NavigationStack`. So
    /// the injection stays at the app root, where it has always worked, and *what* is injected is
    /// per calendar. Injecting below the stack instead is the obvious tidier-looking move and it
    /// traps: `_assertionFailure` inside `EnvironmentValues.subscript.getter`, with no app frame in
    /// the crash report at all, for every pushed editor.
    var currentEventSelection: PCEventSelectionManager {
        eventSelection(for: currentCalendarID)
    }

    /// Ends `calendarID`'s multi-select session, deleting its batch if it ended up with no days.
    ///
    /// Called when a calendar is left — Back on iPhone, a switch on iPad — because a session is
    /// only meaningful while its calendar is on screen, and a cached store means the session
    /// would otherwise still be there on return: the picker and the painted days reappearing
    /// with no way to end them.
    ///
    /// The deletion is the point of routing through here rather than letting the view decide.
    /// A session whose days were all toggled back off has already had its row removed by the
    /// tap that removed the last day, so this normally finds nothing to do — but that is an
    /// inference about a *previous* action, and this is the boundary where the session's life
    /// ends. Making the guarantee here means "no event-less batch outlives its session" is one
    /// statement in one place rather than a property every exit path has to remember.
    func endSession(for calendarID: Int64) {
        eventSelections[calendarID]?.send(.cancelMultiSelectTapped)
    }

    /// Records the calendar that is on screen, so the next launch can reopen it.
    ///
    /// Driven from `RootNavigation.onCalendarChanged`, which fires *inside* the navigation mutation
    /// and passes `nil` when a calendar closes — so forgetting the selection needs no second path,
    /// and archiving or deleting the calendar on screen already covers itself.
    ///
    /// Takes the optional rather than `currentCalendarID`. The sentinel is `0`, and storing it would
    /// put a value into the settings that no calendar can have; the hook's `nil` is the honest
    /// "nothing is on screen" and it is what the store removes.
    func rememberSelectedCalendar(_ id: Int64?) {
        settings.lastSelectedCalendarId = id
    }

    /// The remembered calendar to reopen on launch, or `nil` to open with nothing selected.
    ///
    /// A remembered id is a claim about the past, so it is checked before it is acted on: the
    /// calendar can have been deleted from another install, or archived since. Restoring an id that
    /// no longer resolves is the blank-detail-column failure described on
    /// `RootNavigation.closeCalendarIfSelected`, except with nothing on screen to clear it — so a
    /// stale id is *forgotten* here rather than left to render as an empty column.
    ///
    /// Validated with a point lookup on `persistence` rather than `loadActive()`. The list loads
    /// overwrite the cache's current list and broadcast a refresh to every subscriber, so asking
    /// this question that way would be answering it by disturbing the screen that is about to be
    /// drawn. The lookup is a read, and it does not care whether the calendar is archived: the
    /// archived list can select a calendar too (`RootContentView`), and dropping a selection on the
    /// strength of which list the user happened to pick it from would be surprising.
    ///
    /// Deliberately clears the key on a calendar that is genuinely gone, and deliberately does not
    /// clear it when the read itself fails: a read that failed is not evidence the calendar is gone,
    /// and forgetting the user's selection over a transient error would lose it for good.
    ///
    /// Returns the id rather than opening it, because *how* a calendar is opened is
    /// `RootNavigation`'s business — this type decides what is worth opening, not where.
    func selectedCalendarToRestore() async -> Int64? {
        if let forced = Self.forcedSelectedCalendarIdForUITests {
            settings.lastSelectedCalendarId = forced
        } else if Self.restoringSelectionDisabledForUITests {
            settings.lastSelectedCalendarId = nil
            return nil
        }

        guard let id = settings.lastSelectedCalendarId else { return nil }

        do {
            guard try await persistence.calendar(id: id) != nil else {
                settings.lastSelectedCalendarId = nil
                return nil
            }
        } catch {
            // Nothing to report and nothing to retry: opening with no calendar selected is exactly
            // what the app has always done, so this is the honest answer rather than a swallowed
            // error. It is also why `RootView` can call this from a `.task` with no error path of
            // its own — the one place a failed read is allowed to go nowhere.
            return nil
        }

        return id
    }

    /// The app's settings store, as `SettingsFeature` sees it.
    ///
    /// Built here rather than in `PinCalAppApp` so this stays the one place that decides what the
    /// app's dependencies *are*, beside `makeColumnCountResolver` and `makeNameAutosaveDelay` — the
    /// composition root injects what this hands it and names nothing itself.
    ///
    /// The port is declared in `SettingsFeature` and the type is in `CorePersistence`, so this is
    /// the only place that sees both — and `SettingsStoreConformance` is where the two are joined.
    /// It is also the only place `.standard` is chosen: every setting is read and written through
    /// this one store, so a second store over a different domain would split the user's preferences
    /// in two and the app would disagree with itself about what is set.
    ///
    /// **The place to change when a second backend arrives**, and nothing else would have to move: a
    /// second type conforming to the port, and a `switch` here. There is deliberately no flag for
    /// choosing between them yet — with one backend a switch would be a decision about nothing, and
    /// a preference read from `UserDefaults` would be self-defeating for a store whose point is to
    /// leave `UserDefaults`.
    static func makeSettingsStore() -> any SettingsPersisting {
        UserDefaultsSettingsStore(defaults: .standard)
    }

    /// Resolves the year-grid column count. UI tests can force a specific count
    /// (e.g. a single column so the day cells are large and reliably tappable)
    /// via `-UITestColumns <n>`; otherwise the calendar's natural count is used.
    ///
    /// Used by the composition root to build the session's collaborators, so the
    /// override reaches the shared managers as well.
    static func makeColumnCountResolver() -> (Int) -> Int {
        { requested in forcedColumnsForUITests ?? requested }
    }

    /// Resolves how long a typed name waits before it is written.
    ///
    /// UI tests pass `-UITestNameAutosaveSeconds 0` so a name lands on the next scheduler
    /// pass rather than a quarter of a second later. The delay is real in production and is
    /// not something to hide in the test suite by moving the debounce into the view layer:
    /// durability belongs to the store, which outlives the editor, and a view-owned timer dies
    /// with the view. Making the interval injectable keeps that honest and still lets a test
    /// be deterministic.
    static func makeNameAutosaveDelay() -> Duration {
        forcedNameAutosaveForUITests ?? PCNameAutosave.defaultDelay
    }

    private static var forcedNameAutosaveForUITests: Duration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-UITestNameAutosaveSeconds"),
            arguments.indices.contains(flagIndex + 1),
            let seconds = Double(arguments[flagIndex + 1]),
            seconds >= 0
        else { return nil }
        return .seconds(seconds)
    }

    /// Resolves the archive-undo toast's window. UI tests can lengthen it via
    /// `-UITestUndoWindowSeconds <n>`; otherwise the production 5s window applies.
    ///
    /// Same reasoning as `-UITestColumns`, and for the same reason it matters more here: a
    /// toast is transient, so a test that has to find it inside a 5-second window is a test
    /// that will flake on a loaded simulator and then be ignored. A long window makes the
    /// toast simply *there*, and production is untouched.
    static func makeUndoWindowDuration() -> TimeInterval {
        forcedUndoWindowForUITests ?? 5
    }

    private static var forcedUndoWindowForUITests: TimeInterval? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-UITestUndoWindowSeconds"),
            arguments.indices.contains(flagIndex + 1),
            let value = TimeInterval(arguments[flagIndex + 1]),
            value > 0
        else { return nil }
        return value
    }

    private static var forcedColumnsForUITests: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-UITestColumns"),
            arguments.indices.contains(flagIndex + 1),
            let value = Int(arguments[flagIndex + 1])
        else { return nil }
        return value
    }

    /// The calendar a UI test wants remembered, from `-UITestSelectedCalendar <id>`.
    ///
    /// Seeded into the settings and then read back through the ordinary path, so what the test
    /// exercises is the production restore — read, validate, switch — rather than a stand-in for
    /// it. Seeding it here is also the only way it can be seeded: a UI test runs in its own process
    /// and cannot write the app's preferences.
    private static var forcedSelectedCalendarIdForUITests: Int64? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-UITestSelectedCalendar"),
            arguments.indices.contains(flagIndex + 1),
            let value = Int64(arguments[flagIndex + 1]),
            value > 0
        else { return nil }
        return value
    }

    /// Whether a seeded launch should restore nothing.
    ///
    /// A seeded launch points the calendar store at a *fresh temporary directory*
    /// (`UITestStoreFactory`), so every launch is a different database whose ids start at 1 again.
    /// A remembered id from an earlier run therefore either names nothing at all or names a
    /// different calendar that happens to share the number — and in the second case the app opens a
    /// calendar no test asked for, on a phone in the detail column rather than the list, which is
    /// enough to strand every test that starts by tapping a sidebar row.
    ///
    /// Keyed off the seeding flag rather than a flag of its own, because that flag already means
    /// "this is a throwaway database": a remembered selection from another database is not stale
    /// there, it is meaningless. Preferences are also *not* reset between launches, so this also
    /// keeps one test's selection out of the next one's launch.
    private static var restoringSelectionDisabledForUITests: Bool {
        UITestStoreFactory.shouldSeedForUITests() && forcedSelectedCalendarIdForUITests == nil
    }
}
