//
//  SettingsPersistingEnvironment.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 04.10.2026.
//

import SwiftUI

public extension EnvironmentValues {
    /// The settings port, injected once at the app root.
    ///
    /// Optional because `@Environment` demands a value and there is no other way to inject one —
    /// the same reason `PCAppSession.currentEventSelection` is non-optional and still returns an
    /// inert placeholder for calendar `0`. Nothing in the app runs without the root injection, so
    /// `nil` here is a wiring mistake rather than a state to design a screen around;
    /// `SettingsView` asserts on it rather than quietly rendering an empty form.
    ///
    /// A value and not an environment *object*, and deliberately so. `.environment(_:)` requires
    /// `Observable`, and a protocol cannot be constrained to it — so the object form is not available
    /// for an existential at all. It is not needed either: the injected value is only transport, and
    /// observation rides on the concrete store. A view reads `store.theme` during `body`, the
    /// concrete `@Observable` getter registers it, and the view re-renders when the value changes.
    /// Injecting an object here would add nothing that the value does not already do.
    ///
    /// Main-actor isolated, because the port is. Everything that reads settings is a view or a
    /// main-actor session, so the isolation costs nothing and is what makes the store safe to mutate
    /// from a view while it is being rendered.
    @Entry var settingsPersisting: (any SettingsPersisting)?
}
