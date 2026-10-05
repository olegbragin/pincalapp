//
//  SettingsViewModelTests.swift
//  SettingsFeatureTests
//
//  Created by Oleg Bragin on 08.09.2026.
//

import Foundation
import SwiftUI
import Testing
import DSKit
// `@testable` because `SettingsViewModel` is internal to the package — deliberately, so nothing
// outside it can build a second holder over the shared store.
@testable import SettingsFeature

/// An in-memory `SettingsPersisting`.
///
/// Three properties and nothing else, because the port names settings and no caller names a key —
/// the store is the only thing that has ever known what they are called.
///
/// `@MainActor`, which is what the port requires. This suite used to need `@unchecked Sendable` and a
/// paragraph explaining why unchecked was honest for a test double; the main-actor port removed the
/// question rather than answering it, because a main-actor type is properly `Sendable`.
@MainActor
private final class SettingsStoreStub: SettingsPersisting {
    var lastSelectedTheme: String?
    var lastSelectedVibeId: String?
    var lastSelectedCalendarId: Int64?

    init(
        lastSelectedTheme: String? = nil,
        lastSelectedVibeId: String? = nil,
        lastSelectedCalendarId: Int64? = nil
    ) {
        self.lastSelectedTheme = lastSelectedTheme
        self.lastSelectedVibeId = lastSelectedVibeId
        self.lastSelectedCalendarId = lastSelectedCalendarId
    }
}

@MainActor
@Suite("SettingsViewModel Tests")
struct SettingsViewModelTests {
    @Test("reads the theme through to the store")
    func readsTheme() {
        let store = SettingsStoreStub(lastSelectedTheme: AppTheme.dark.rawValue)

        let vm = SettingsViewModel(store: store)

        #expect(vm.theme == .dark)
    }

    @Test("writing the theme writes the store")
    func writesTheme() {
        let store = SettingsStoreStub()

        SettingsViewModel(store: store).theme = .light

        #expect(store.lastSelectedTheme == AppTheme.light.rawValue)
    }

    @Test("reads the vibe id through to the store")
    func readsVibe() {
        let store = SettingsStoreStub(lastSelectedVibeId: PCVibe.default.id)

        let vm = SettingsViewModel(store: store)

        #expect(vm.vibeId == PCVibe.default.id)
    }

    @Test("writing the vibe id writes the store")
    func writesVibe() {
        let store = SettingsStoreStub()

        SettingsViewModel(store: store).vibeId = "default"

        #expect(store.lastSelectedVibeId == "default")
    }

    /// The relay holds no state of its own, so it cannot fall out of step with the store.
    ///
    /// Worth pinning because the alternative shape — a holder with its own `theme` written through in
    /// `didSet` — passed every other test in this file while being a second copy of the truth. What
    /// distinguishes them is only observable from outside the model: writing the *store* has to change
    /// what the model reads, and writing the model has to change what the store holds.
    @Test("the relay holds no state of its own")
    func holdsNoStateOfItsOwn() {
        let store = SettingsStoreStub(lastSelectedTheme: AppTheme.light.rawValue)
        let vm = SettingsViewModel(store: store)

        store.lastSelectedTheme = AppTheme.dark.rawValue

        #expect(vm.theme == .dark, "a write to the store must be visible through the model")
    }

    /// The pickers cannot use `@Bindable`, so the model hands them bindings instead.
    ///
    /// `@Bindable` needs stored observable properties and cannot be applied to `any
    /// SettingsPersisting` at all, so these are the only way a `Picker` can reach the store — which
    /// makes them load-bearing rather than a convenience, and worth a test that they write.
    @Test("the bindings write to the store")
    func bindingsWriteThrough() {
        let store = SettingsStoreStub(lastSelectedVibeId: PCVibe.default.id)
        let vm = SettingsViewModel(store: store)

        vm.themeBinding.wrappedValue = .dark
        vm.vibeBinding.wrappedValue = "default"

        #expect(store.lastSelectedTheme == AppTheme.dark.rawValue)
        #expect(store.lastSelectedVibeId == "default")
    }

    @Test("the bindings read from the store")
    func bindingsReadThrough() {
        let store = SettingsStoreStub(lastSelectedTheme: AppTheme.light.rawValue, lastSelectedVibeId: "default")
        let vm = SettingsViewModel(store: store)

        #expect(vm.themeBinding.wrappedValue == .light)
        #expect(vm.vibeBinding.wrappedValue == "default")
    }

    /// The two settings are separate, and a write to one must not disturb the other.
    ///
    /// They share a store and nothing else, so this is the cheap guard against a relay being wired to
    /// the wrong setting — which would look correct in every other test here, since each of them only
    /// ever writes one of the two.
    @Test("writing the theme leaves the vibe alone")
    func writingThemeLeavesVibeAlone() {
        let store = SettingsStoreStub(lastSelectedVibeId: "default")
        let vm = SettingsViewModel(store: store)

        vm.theme = .dark

        #expect(store.lastSelectedVibeId == "default")
        #expect(vm.vibeId == "default")
    }
}
