//
//  USCalendarPinchToZoomGesture.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 26.03.2026.
//

import SwiftUI
import UIKit

struct USCalendarPinchToZoomGesture: Gesture {
    @State var viewModel: USCalendarPinchToZoomGestureModel
    // Для тактильной отдачи (опционально)
    private let hapticFeedback = UINotificationFeedbackGenerator()
    
    // Временный масштаб во время жеста (сбрасывается после)
    @GestureState private var tempMagnification: CGFloat
    @State private var gestureStartTime: Date?
    
    @Binding var numberOfColumns: Int
    
    init(
        tempMagnification: GestureState<CGFloat>,
        numberOfColumns: Binding<Int>,
    ) {
        self._tempMagnification = tempMagnification
        self._numberOfColumns = numberOfColumns
        self.viewModel = USCalendarPinchToZoomGestureModel(numberOfColumns: numberOfColumns.wrappedValue)
    }
    
    var body: some Gesture {
        MagnifyGesture()
            .updating($tempMagnification) { value, state, _ in
                state = value.magnification
                if gestureStartTime == nil {
                    gestureStartTime = Date()
                }
            }
            .onEnded { value in
                let duration = Date().timeIntervalSince(gestureStartTime ?? Date())
                viewModel.handleMagnify(
                    magnification: value.magnification,
                    velocity: value.velocity,
                    gestureDuration: duration,
                    didChange: {
                        numberOfColumns = $0
                        // Дополнительный визуальный отклик (можно анимировать)
                        hapticFeedback.notificationOccurred(.success)
                    }
                )
                gestureStartTime = nil
            }
    }
}
