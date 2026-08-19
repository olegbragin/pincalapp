//
//  SingleCalendarEditorContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct SingleCalendarEditorContent: View {
    var viewModel: AddEditEventBatchListViewModel
    var onClose: () -> Void
    var onBatchTap: () -> Void

    var body: some View {
        AddEditEventBatchListView(
            viewModel: viewModel,
            onClose: onClose,
            onBatchTap: onBatchTap
        )
    }
}

#Preview {
    SingleCalendarEditorContent(
        viewModel: AddEditEventBatchListViewModel(),
        onClose: {},
        onBatchTap: {}
    )
}
