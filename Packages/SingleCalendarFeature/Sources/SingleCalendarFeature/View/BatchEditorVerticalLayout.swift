//
//  BatchEditorVerticalLayout.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI
import DSKit

public struct BatchEditorVerticalLayout: View {
    var viewModel: AddEditEventBatchViewModel
    public var onSave: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            PCCalendarYearView(viewModel: viewModel.yearModel)
                .accessibilityIdentifier("batch-editor-calendar")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AddEditEventBatchView(
                viewModel: viewModel,
                onSave: onSave
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    BatchEditorVerticalLayout(
        viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]),
        onSave: {}
    )
    .environment(PCKeyboardState())
}
