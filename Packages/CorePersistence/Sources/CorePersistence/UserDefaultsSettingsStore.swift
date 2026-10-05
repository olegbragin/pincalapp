//
//  UserDefaultsSettingsStore.swift
//  CorePersistence
//

import Foundation
import Observation

/// The app's settings, kept in `UserDefaults`.
///
/// Observable, so a view that reads a property during `body` re-renders when it changes — which is
/// what lets the app root apply the theme and the vibe without a second copy of them. Nothing here
/// knows what a setting *means*: three raw values and the writes that persist them.
///
/// **No feature vocabulary, deliberately.** `AppTheme` and `PCVibe` are not visible from this
/// package and must not become visible from it. A storage type that produced an `AppTheme` would
/// have to import `SettingsFeature`, which imports SwiftUI, and one that produced a vibe id would
/// have to import `DSKit`, which also imports SwiftUI — so the vocabulary of the interface would
/// follow the data into the persistence layer and every package that persists anything would drag
/// SwiftUI in behind it. The three raw strings below are the whole contract; decoding a stored value
/// into a domain type is the feature's job, in `SettingsFeature`, and it is the only place an
/// unrecognised value can be caught.
///
/// Named for its role rather than its technology, matching `CalendarStore` — itself ObjectBox-backed
/// and likewise not named for that.
///
/// `@MainActor` because it is observable state that views read while rendering, and because an
/// observable type has to be isolated to be safe to mutate from a view. That also makes it
/// implicitly `Sendable`, which is why the port in `SettingsFeature` can require the same and this
/// type needs no annotation.
@MainActor
@Observable
public final class UserDefaultsSettingsStore {
    private static let themeKey = "appTheme"
    private static let vibeKey = "appVibe"
    private static let selectedCalendarIdKey = "lastSelectedCalendarId"

    /// The stored theme, as its raw value. A value this package cannot judge is kept as written and
    /// decoded by whoever reads it — see the type's doc.
    public var lastSelectedTheme: String? {
        didSet {
            guard lastSelectedTheme != oldValue else { return }
            defaults.set(lastSelectedTheme, forKey: Self.themeKey)
        }
    }

    /// The stored vibe id, as written.
    public var lastSelectedVibeId: String? {
        didSet {
            guard lastSelectedVibeId != oldValue else { return }
            defaults.set(lastSelectedVibeId, forKey: Self.vibeKey)
        }
    }

    /// The stored calendar id.
    ///
    /// `nil` removes the key rather than storing a placeholder. Storing an empty string would make
    /// "the selection was cleared" indistinguishable from "something was stored", and the two are
    /// not the same answer: the first means the next launch opens nothing.
    public var lastSelectedCalendarId: Int64? {
        didSet {
            guard lastSelectedCalendarId != oldValue else { return }
            guard let lastSelectedCalendarId else {
                defaults.removeObject(forKey: Self.selectedCalendarIdKey)
                return
            }
            defaults.set(lastSelectedCalendarId, forKey: Self.selectedCalendarIdKey)
        }
    }

    /// Carried rather than observed: `@Observable` only instruments `var`, and reading a
    /// `UserDefaults` is not view state.
    @ObservationIgnored
    private let defaults: UserDefaults

    /// Seeds every property from storage, without writing any of it back.
    ///
    /// `didSet` does not fire for the initial assignment, which is what keeps a read from looking
    /// like a write — a store that rewrote its keys on every launch would make "the user never set
    /// this" indistinguishable from "the user set this to its default".
    ///
    /// `selectedCalendarId` is read through `object(forKey:)` rather than `integer(forKey:)`, which
    /// answers `0` for a key that was never written — and `0` is the sentinel `PCAppSession` uses
    /// for "no calendar on screen", so the two would be indistinguishable here.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastSelectedTheme = defaults.string(forKey: Self.themeKey)
        self.lastSelectedVibeId = defaults.string(forKey: Self.vibeKey)
        self.lastSelectedCalendarId = (defaults.object(forKey: Self.selectedCalendarIdKey) as? NSNumber)?.int64Value
    }
}
