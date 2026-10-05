//
//  SettingsPersisting.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 04.10.2026.
//

/// Where the user's settings live, as this feature needs them.
///
/// Deliberately says nothing about *what* stores them. The name follows `CalendarPersisting`, and
/// for the same reason: a port names the capability, never the technology behind it. So this is
/// `SettingsPersisting` and not `UserDefaultsPersisting`, which would have pinned the abstraction
/// to the one implementation that exists today and made renaming either one a breaking change.
///
/// Declared here, in the package that consumes it, rather than beside the implementation.
/// `CorePersistence` supplies the store and this package never names that module — so which storage
/// backs settings stays a composition-root decision rather than a fact this feature compiles
/// against. That is the same seam `CalendarManaging` draws.
///
/// **Three raw settings, and no feature vocabulary.** Every value crosses as the string or integer
/// it is stored as. `AppTheme` and `PCVibe` are deliberately absent, and this package is what keeps
/// them out of the store: a persistence type that produced an `AppTheme` would have to import this
/// package, and this package imports SwiftUI, so the interface's vocabulary would follow the data
/// down into storage. The decoding lives in `SettingsPersisting+Decoded`, which means the *only*
/// place in the app that can reject an unrecognised stored value is here.
///
/// **`@MainActor`, and that is load-bearing.** The implementation is observable, because the app root
/// renders the theme and the vibe and has to see a change to either; an observable type has to be
/// isolated to be safe to mutate from a view, so the port has to be too. It also settles the
/// `Sendable` question for free — a main-actor type is implicitly `Sendable` — where the previous
/// `Sendable`-but-not-isolated shape forced both the store and its test doubles into
/// `@unchecked`, with a paragraph each explaining why that was acceptable.
///
/// Three properties rather than six methods, each read and written as a value. An earlier shape had a
/// getter and a setter method per setting, and the setter methods were the awkward half: a stored
/// property cannot satisfy a `setSomething(_:)` requirement, so the adapter had to spell them out
/// separately for no gain. Written as `{ get set }` the port reads as what it is, and an adapter
/// that is already a property satisfies it with an empty conformance.
///
/// **`AnyObject`, and that is not decoration.** A setting is *written*, and Swift will not call a
/// setter through a `let` of a protocol existential that might be a value type — `store.theme = .dark`
/// fails to compile with "cannot assign to property: 'store' is a 'let' constant". Class-constraining
/// the port says what is true anyway: the implementation is an `@Observable` class, which has to be a
/// class to be observable at all. Without the constraint every consumer would have to hold the store
/// in a `var` to be able to change a setting, which is a worse answer to the same problem.
@MainActor
public protocol SettingsPersisting: AnyObject {
    /// The theme the user last chose, as its raw value, or `nil` when never written.
    var lastSelectedTheme: String? { get set }

    /// The id of the vibe the user last chose, or `nil` when never written.
    var lastSelectedVibeId: String? { get set }

    /// The id of the calendar that was last on screen, or `nil` when there is none.
    ///
    /// Assigning `nil` forgets the selection, which is a state distinct from never having had one:
    /// the calendar was closed, so the next launch must not bring it back.
    var lastSelectedCalendarId: Int64? { get set }
}
