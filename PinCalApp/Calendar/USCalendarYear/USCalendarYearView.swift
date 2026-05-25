//
//  USCalendarYear.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 25.01.2026.
//

import SwiftUI
import OrderedCollections

struct USCalendarYearView: View {
    @Bindable var viewModel: USCalendarYearModel
    
    // Временный масштаб во время жеста (сбрасывается после)
    @GestureState private var tempMagnification: CGFloat = 1.0
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12),
                        count: viewModel.internalNumberOfColumns
                    ),
                    spacing: 32
                ) {
                    ForEach(viewModel.months.indices, id: \.self) { index in
                        let month = viewModel.months[index]
                        USCalendarMonthView(
                            viewModel: month
                        )
                        .id(index)
                    }
                }
                .padding(16)
            }
            .scrollTargetLayout()
            .onAppear {
                if let index = viewModel.indexOfCurrentMonth {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo(index, anchor: .top)
                    }
                }
            }
            .onChange(of: viewModel.numberOfColumns) {
                if let index = viewModel.indexOfCurrentMonth {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo(index, anchor: .top)
                    }
                }
            }
            .highPriorityGesture(
                USCalendarPinchToZoomGesture(
                    tempMagnification: $tempMagnification,
                    numberOfColumns: $viewModel.numberOfColumns
                )
            )
            .animation(.easeOut(duration: 0.3), value: viewModel.numberOfColumns)
        }
    }
}
