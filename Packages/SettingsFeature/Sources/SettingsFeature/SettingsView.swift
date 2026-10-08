//
//  SettingsView.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 08.09.2026.
//

import SwiftUI
import DSKit

public struct SettingsView: View {
    /// The app's settings, as the port this feature declares.
    ///
    /// Injected at the app root and observed, not copied: the store is `@Observable`, so a read
    /// during `body` re-renders this screen *and* the app root when the theme or the vibe changes.
    /// That is why the port exposes values rather than a prepared model — a model handed in would be
    /// a second holder, and two holders over one store is the arrangement this design exists to
    /// avoid.
    @Environment(\.settingsPersisting) private var store
    @State private var viewModel: SettingsViewModel?

    /// Spelled out because a `public struct` gets an *internal* memberwise initialiser once all its
    /// stored properties are property wrappers, and `SettingsView()` is called from the app target —
    /// which would otherwise not compile.
    public init() {}

    public var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                PCProgressView(label: "Loading")
            }
        }
        .task {
            // Built here rather than in `init` because `@Environment` is not readable from an
            // initialiser — the same trade `CalendarDetailView` and `CalendarListView` make.
            guard viewModel == nil else { return }
            guard let store else {
                // Not a state this screen should render. The app root injects unconditionally, so a
                // `nil` here means the wiring was changed and the injection missed — and silently
                // spinning on "Loading" would report that as a slow screen rather than as a bug.
                assertionFailure("SettingsView presented without \\.settingsPersisting in the environment.")
                return
            }
            viewModel = SettingsViewModel(store: store)
        }
    }

    private func content(for model: SettingsViewModel) -> some View {
        Form {
            Section(.appearance) {
                Picker(String(localized: .theme), selection: model.themeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.localizedTitle)
                            .tag(theme)
                    }
                }
                // Only the picker's own label is a UI string. `vibe.name` is data — a custom
                // vibe carries the name its author gave it, which is not this catalog's to
                // translate, so it stays a plain value.
                Picker(String(localized: .vibe), selection: model.vibeBinding) {
                    ForEach(PCVibe.all) { vibe in
                        Text(vibe.name)
                            .tag(vibe.id)
                    }
                }
            }
        }
        .navigationTitle(String(localized: .settings))
        .pcNavigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.settingsPersisting, PreviewSettingsStore())
}

/// Backs the preview, and only the preview.
///
/// `SettingsView` reads the port from the environment, so a preview without one sits on "Loading"
/// forever — which reads as a broken screen rather than as a missing fixture.
///
/// `MainActor` rather than the `@unchecked Sendable` this used to need: the port is main-actor
/// isolated now, so a conformance has to be, and a main-actor type is `Sendable` properly. That is a
/// strict improvement over asserting thread-safety the fixture did not have — the old version's doc
/// had to explain why unchecked was honest *here* and would not be anywhere else.
@MainActor
private final class PreviewSettingsStore: SettingsPersisting {
    var lastSelectedTheme: String? = AppTheme.system.rawValue
    var lastSelectedVibeId: String?
    var lastSelectedCalendarId: Int64?
}
