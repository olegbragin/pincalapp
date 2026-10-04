//
//  SettingsView.swift
//  SettingsFeature
//
//  Created by Oleg Bragin on 08.09.2026.
//

import SwiftUI
import DSKit

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    public init() {
        // The app's real preferences. Stated here rather than defaulted inside
        // `SettingsViewModel` so this remains the single place that opts into the
        // process-wide store — see the note on that initialiser.
        _viewModel = State(initialValue: SettingsViewModel(defaults: .standard))
    }

    public var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $viewModel.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title)
                            .tag(theme)
                    }
                }
                Picker("Vibe", selection: $viewModel.vibeId) {
                    ForEach(PCVibe.all) { vibe in
                        Text(vibe.name)
                            .tag(vibe.id)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .pcNavigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
