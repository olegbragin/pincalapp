import Foundation
import Testing
import DSKit
import SettingsFeature

@MainActor
@Suite("SettingsViewModel Tests")
struct SettingsViewModelTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("defaults to system when nothing is stored")
    func defaultsToSystem() {
        let defaults = makeDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        #expect(vm.theme == .system)
    }

    @Test("reads a persisted value")
    func readsPersisted() {
        let defaults = makeDefaults()
        defaults.set(AppTheme.dark.rawValue, forKey: SettingsViewModel.themeKey)

        let vm = SettingsViewModel(defaults: defaults)

        #expect(vm.theme == .dark)
    }

    @Test("setting the theme persists")
    func persistsTheme() {
        let defaults = makeDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        vm.theme = .light

        #expect(defaults.string(forKey: SettingsViewModel.themeKey) == AppTheme.light.rawValue)
    }

    @Test("defaults to the default vibe when nothing is stored")
    func defaultsToDefaultVibe() {
        let defaults = makeDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        #expect(vm.vibeId == PCVibe.default.id)
    }

    @Test("reads a persisted vibe id")
    func readsPersistedVibe() {
        let defaults = makeDefaults()
        defaults.set("custom-vibe", forKey: SettingsViewModel.vibeKey)

        let vm = SettingsViewModel(defaults: defaults)

        #expect(vm.vibeId == "custom-vibe")
    }

    @Test("setting the vibe persists")
    func persistsVibe() {
        let defaults = makeDefaults()
        let vm = SettingsViewModel(defaults: defaults)

        vm.vibeId = "dark-vibe"

        #expect(defaults.string(forKey: SettingsViewModel.vibeKey) == "dark-vibe")
    }
}
