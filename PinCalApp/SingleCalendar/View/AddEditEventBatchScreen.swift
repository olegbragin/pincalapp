//
//  AddEditEventBatchScreen.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.08.2026.
//

import SwiftUI

struct AddEditEventBatchScreen: View {
    @Bindable var viewModel: AddEditEventBatchViewModel
    
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                horizontalLayout
            } else {
                verticalLayout
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                titleContent
            }
        }
        .toolbarBackground(Color("colorBackgroundMain"), for: .navigationBar)
        .ignoresSafeArea(edges: .bottom)
        .background(.colorBackgroundMain)
        .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
            if let selectedDay = newValue.first {
                viewModel.toggleEvent(on: selectedDay)
            }
        }
    }
    
    private var verticalLayout: some View {
        VStack(spacing: 0) {
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AddEditEventBatchView(
                viewModel: viewModel,
                onSave: onSave
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AddEditEventBatchView(
                viewModel: viewModel,
                onSave: onSave
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var calendarContent: some View {
        USCalendarYearView(
            viewModel: viewModel.yearModel
        )
        .accessibilityIdentifier("batch-editor-calendar")
    }
    
    private var titleContent: some View {
        ViewThatFits(in: .horizontal) {
            preferredTitle
            compactTitle
        }
    }
    
    @ViewBuilder
    private var preferredTitle: some View {
        if let title = viewModel.preferredTitle {
            Text(title)
                .font(.headline)
                .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var compactTitle: some View {
        if let title = viewModel.compactTitle {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

#Preview {
    NavigationStack {
        AddEditEventBatchScreen(
            viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")])
        )
    }
}
