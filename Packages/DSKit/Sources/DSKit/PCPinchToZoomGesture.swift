//
 //  PCPinchToZoomGesture.swift
 //  PinCalApp
 //
 //  Created by Oleg Bragin on 26.03.2026.
 //

import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct PCPinchToZoomGesture: Gesture {
    @State private var viewModel: PCPinchToZoomGestureModel

    @GestureState private var tempMagnification: CGFloat
    @State private var gestureStartTime: Date?

    public init(
        tempMagnification: GestureState<CGFloat>,
        onPinchedToZoomIn: @escaping () -> Void,
        onPinchedToZoomOut: @escaping () -> Void
    ) {
        self._tempMagnification = tempMagnification
#if os(iOS)
        let feedback = UINotificationFeedbackGenerator()
        self._viewModel = State(
            initialValue: PCPinchToZoomGestureModel(
                onPinchedToZoomIn: {
                    feedback.notificationOccurred(.success)
                    onPinchedToZoomIn()
                },
                onPinchedToZoomOut: {
                    feedback.notificationOccurred(.success)
                    onPinchedToZoomOut()
                }
            )
        )
#else
        self._viewModel = State(
            initialValue: PCPinchToZoomGestureModel(
                onPinchedToZoomIn: onPinchedToZoomIn,
                onPinchedToZoomOut: onPinchedToZoomOut
            )
        )
#endif
    }

    public var body: some Gesture {
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
                    gestureDuration: duration
                )
                gestureStartTime = nil
            }
    }
}