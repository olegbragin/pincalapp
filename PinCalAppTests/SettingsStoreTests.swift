//
//  SettingsStoreTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 04.10.2026.
//

import Foundation
import Testing
import SettingsFeature
@testable import CorePersistence
// `@testable` for the conformance, which lives in the app target beside `CalendarStore`.
@testable import PinCalApp

/// Covers the settings store and the conformance that makes it a `SettingsPersisting`.
///
/// It has almost no logic — three properties that write through — which is exactly why it needs
/// these: a conformance that compiles is not a conformance that writes where it claims to. The
/// suites that exercise the behaviour *above* it (`SettingsViewModelTests`,
/// `SettingsPersistingDecodingTests`) run against in-memory stubs and would keep passing if this type
/// silently dropped every write.
///
/// Lives here rather than in `CorePersistenceTests` for two reasons. The type is in `CorePersistence`
/// but the conformance that makes it usable is in the app target, and it is the conformance that is
/// under test — so this is where both are visible. And it is the app target's job to decide that
/// this store is the app's settings, which is the decision the literal key names below belong to.
/// A counter for an observation callback.
///
/// `@unchecked Sendable` because `withObservationTracking`'s `onChange` closure is `@Sendable` and a
/// test-local `var` cannot be captured by one. The callback is invoked synchronously, on the thread
/// that made the change, so there is no second thread to race with — the annotation satisfies the
/// signature rather than asserting a safety the test has not checked.
private final class NotificationCounter: @unchecked Sendable {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
struct SettingsStoreTests {
    /// A private suite per test, so nothing here can reach — or be reached by — the real
    /// preferences. `removePersistentDomain` first because a suite name is reusable: a previous run
    /// leaving `"dark"` behind would make `readsBackWhatWasWritten` pass without a write happening.
    private func makeStore() -> (store: any SettingsPersisting, defaults: UserDefaults, suite: String) {
        let suite = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserDefaultsSettingsStore(defaults: defaults), defaults, suite)
    }

    /// Discards the private suite, so a run cannot leave preferences behind for the next one.
    private func tearDown(_ suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    @Test("reads back what was written")
    func readsBackWhatWasWritten() {
        let (store, _, suite) = makeStore()
        defer { tearDown(suite) }

        #expect(store.lastSelectedTheme == nil)

        store.lastSelectedTheme = "dark"

        #expect(store.lastSelectedTheme == "dark")
    }

    /// The write has to reach the `UserDefaults` the store was handed, not just its own memory.
    ///
    /// Without this, a store that kept everything in a field would pass every other test here and
    /// lose the setting on the next launch — which is the entire reason this type exists alongside
    /// the in-memory stubs the other suites use.
    @Test("a write reaches the underlying defaults")
    func writesThroughToDefaults() {
        let (store, defaults, suite) = makeStore()
        defer { tearDown(suite) }

        store.lastSelectedTheme = "dark"
        store.lastSelectedVibeId = "default"
        store.lastSelectedCalendarId = 7

        #expect(defaults.string(forKey: "appTheme") == "dark")
        #expect(defaults.string(forKey: "appVibe") == "default")
        #expect(defaults.object(forKey: "lastSelectedCalendarId") as? Int == 7)
    }

    /// Two stores must not see each other's writes — the property the whole port exists for.
    ///
    /// Without this, a store that ignored the `UserDefaults` it was handed and used `.standard`
    /// would still pass every other test here, and would write the user's real preferences during a
    /// test run.
    @Test("stores over different suites do not see each other's writes")
    func storesAreIndependent() {
        let first = makeStore()
        let second = makeStore()
        defer {
            tearDown(first.suite)
            tearDown(second.suite)
        }

        first.store.lastSelectedTheme = "light"

        #expect(first.store.lastSelectedTheme == "light")
        #expect(second.store.lastSelectedTheme == nil)
    }

    /// An empty string is a value, not an absence.
    ///
    /// Worth pinning because `lastSelectedTheme` returning `""` rather than `nil` is what stops a
    /// blank preference from reading as "nothing stored" — the caller decides that, and it can only
    /// if the store hands the blank back rather than swallowing it.
    @Test("an empty string round-trips as a value, not as absence")
    func emptyStringIsAValue() {
        let (store, _, suite) = makeStore()
        defer { tearDown(suite) }

        store.lastSelectedTheme = ""

        #expect(store.lastSelectedTheme == "")
    }

    /// An unwritten setting reads as `nil` — and for the calendar id specifically, never as `0`.
    ///
    /// `UserDefaults.integer(forKey:)` answers `0` for a key that was never written, and `0` is the
    /// sentinel `PCAppSession` uses for "no calendar". A store built on it would make "no calendar
    /// was ever selected" and "something stored zero" the same answer, and the second is a value no
    /// calendar can have.
    @Test("an unwritten setting reads as nil rather than zero")
    func unwrittenSettingsAreNil() {
        let (store, _, suite) = makeStore()
        defer { tearDown(suite) }

        #expect(store.lastSelectedTheme == nil)
        #expect(store.lastSelectedVibeId == nil)
        #expect(store.lastSelectedCalendarId == nil)
    }

    /// Forgetting removes the key rather than storing something in its place.
    ///
    /// The distinction is the point of the optional: "the selection was cleared" and "a value is
    /// stored" have to be different answers, or a closed calendar comes back on the next launch.
    @Test("forgetting the selected calendar removes the key")
    func forgettingRemovesTheKey() {
        let (store, defaults, suite) = makeStore()
        defer { tearDown(suite) }
        store.lastSelectedCalendarId = 42
        #expect(store.lastSelectedCalendarId == 42)

        store.lastSelectedCalendarId = nil

        #expect(store.lastSelectedCalendarId == nil)
        #expect(defaults.object(forKey: "lastSelectedCalendarId") == nil)
    }

    /// The keys are the app's storage format, pinned against their literal strings.
    ///
    /// Asserted against literals rather than against the store's own constants: a test that compared
    /// the two would pass after both were renamed, which is exactly the case this exists to catch.
    /// Renaming a key drops that setting for every existing install — silently, since a setting
    /// nobody has set yet cannot be observed to be missing.
    @Test("settings are written under the documented keys")
    func writesUnderTheDocumentedKeys() {
        let (store, defaults, suite) = makeStore()
        defer { tearDown(suite) }

        store.lastSelectedTheme = "light"
        store.lastSelectedVibeId = "default"
        store.lastSelectedCalendarId = 7

        #expect(defaults.string(forKey: "appTheme") == "light")
        #expect(defaults.string(forKey: "appVibe") == "default")
        #expect(defaults.object(forKey: "lastSelectedCalendarId") as? Int == 7)
    }

    /// Reading at launch must not count as writing.
    ///
    /// A store whose initialiser wrote back would make "the user never set this" indistinguishable
    /// from "the user set this to its default", and it would rewrite storage on every launch — from
    /// the one place that is supposed never to write unless asked.
    @Test("seeding from storage does not write back")
    func seedingDoesNotWrite() throws {
        let suite = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { tearDown(suite) }

        _ = UserDefaultsSettingsStore(defaults: defaults)

        #expect(defaults.object(forKey: "appTheme") == nil)
        #expect(defaults.object(forKey: "appVibe") == nil)
        #expect(defaults.object(forKey: "lastSelectedCalendarId") == nil)
    }

    /// The property the whole observable design exists for: a change must be *observable*.
    ///
    /// `RootView` reads the theme during `body` and relies on this to re-render when the user picks a
    /// different one. That is not something a plain `UserDefaults` forwarder can do — it holds no
    /// observable state, so a read from it subscribes to nothing and the window would keep rendering
    /// the launch-time theme until something else happened to re-render it. If this test fails, the
    /// app's appearance stops following the picker.
    ///
    /// Counted rather than awaited. `withObservationTracking` reports **once** per tracking session,
    /// and synchronously at the mutation, so there is nothing to wait for — and a timeout here would
    /// be measuring the machine rather than the behaviour. The re-read after each write is what makes
    /// it independent of whether the notification lands at the mutation or at the next access.
    @Test("a write notifies an observer")
    func writesAreObservable() {
        let (store, _, suite) = makeStore()
        defer { tearDown(suite) }
        let notifications = NotificationCounter()

        withObservationTracking {
            _ = store.lastSelectedTheme
        } onChange: {
            notifications.increment()
        }

        store.lastSelectedTheme = "dark"
        _ = store.lastSelectedTheme

        #expect(notifications.value == 1, "a view reading this during body has to be told it changed")
    }

    /// Writing the value it already holds must not notify anybody.
    ///
    /// Without the guard in `didSet`, assigning the same theme would re-render the whole app — the
    /// settings screen re-reading itself on open, and anything else that touched the value.
    @Test("writing the same value does not notify an observer")
    func writingTheSameValueIsSilent() {
        let (store, _, suite) = makeStore()
        defer { tearDown(suite) }
        store.lastSelectedTheme = "dark"
        let notifications = NotificationCounter()

        withObservationTracking {
            _ = store.lastSelectedTheme
        } onChange: {
            notifications.increment()
        }

        store.lastSelectedTheme = "dark"
        _ = store.lastSelectedTheme

        #expect(notifications.value == 0, "an unchanged value is not a change")
    }
}
