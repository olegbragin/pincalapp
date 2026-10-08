//
//  BatchEditorVerticalLayout.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI
import DSKit

public struct BatchEditorVerticalLayout: View {
    @Environment(PCEventSelectionManager.self) private var store

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventBatchViewModel(store: store)

        VStack(spacing: 0) {
            PCCalendarYearView(
                viewModel: viewModel.yearModel,
                selectYearTitle: String(localized: .selectYear),
                onYearSelect: { viewModel.switchYear(to: $0) }
            )
            .accessibilityIdentifier("batch-editor-calendar")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            AddEditEventBatchView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    BatchEditorVerticalLayout()
        .environment(PCKeyboardState())
}
