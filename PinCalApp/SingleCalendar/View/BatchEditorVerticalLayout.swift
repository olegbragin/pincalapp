//
//  BatchEditorVerticalLayout.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct BatchEditorVerticalLayout: View {
    var viewModel: AddEditEventBatchViewModel
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BatchEditorCalendarContent(viewModel: viewModel.yearModel)
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
}
