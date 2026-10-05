//
//  SettingsViewModel.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 08.09.2026.
//

import Foundation
import Observation
import SwiftUI
import DSKit

/// The settings screen's model: a thin relay onto the shared store.
///
/// **Computed properties only, and that is the point.** This started as a holder of its own
/// `theme` and `vibeId` with `didSet` writing through to storage — two values mirroring two other
/// values, kept in step only because every write was forwarded. The store is observable, so mirroring
/// it buys nothing and costs a second thing to be wrong. Relaying instead means this type holds no
/// state at all, so it cannot disagree with what the app is rendering.
///
/// The bindings exist because of that. `@Bindable` cannot help here: it needs *stored* observable
/// properties, and it cannot be applied to `any SettingsPersisting` either, because `@Bindable`
/// requires `Observable` and a protocol cannot be constrained to it. So the pickers are handed a
/// `Binding` that reads and writes the store directly, which is also one hop shorter than binding to
/// a mirror would have been.
///
/// Internal, deliberately. Nothing outside this package may build one: the store is app-wide and
/// observable, so a second holder over it would be a second answer to the same question with no way
/// to be kept in step.
@MainActor
@Observable
final class SettingsViewModel {
    /// The theme the user last chose, or `.system` when nothing usable is stored.
    var theme: AppTheme {
        get { store.theme }
        set { store.theme = newValue }
    }

    /// The id of the vibe the user last chose, or the default vibe.
    var vibeId: String {
        get { store.vibeId }
        set { store.vibeId = newValue }
    }

    private let store: any SettingsPersisting

    /// `store` is required, with no default, and that is the point of the port.
    ///
    /// This used to take `UserDefaults`, defaulting to `.standard` — so the feature both named the
    /// storage and hardcoded *which* one, and a caller who forgot to pass anything got a view model
    /// reading and writing the user's real settings. Every test happened to pass its own suite, so
    /// nothing was broken; the hazard was one omitted argument away, and the tests were passing
    /// only because they happened to be the careful ones.
    ///
    /// Naming a port moves both decisions out to `PCAppSession`, now the only place that knows what
    /// the app's settings are made of.
    init(store: any SettingsPersisting) {
        self.store = store
    }

    /// The theme picker, bound to the store rather than to a mirror of it.
    var themeBinding: Binding<AppTheme> {
        let store = store
        return Binding(get: { store.theme }, set: { store.theme = $0 })
    }

    /// The vibe picker, bound to the store.
    var vibeBinding: Binding<String> {
        let store = store
        return Binding(get: { store.vibeId }, set: { store.vibeId = $0 })
    }
}
