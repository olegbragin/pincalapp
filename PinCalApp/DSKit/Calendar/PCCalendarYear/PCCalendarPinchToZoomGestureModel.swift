//
//  PCPinchToZoomGestureModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 26.03.2026.
//

import Foundation
import Observation

@Observable
final class PCPinchToZoomGestureModel {
    private let baseSensitivity: CGFloat = 0.12
    private let minSensitivity: CGFloat = 0.08
    private var smoothMagnification: CGFloat = 1.0
    private var accumulatedDelta: CGFloat = 0.0
    private var lastMagnification: CGFloat = 1.0
    private var lastDirection: Int = 0

    var onPinchedToZoomIn: (() -> Void)?
    var onPinchedToZoomOut: (() -> Void)?

    init(
        onPinchedToZoomIn: (() -> Void)? = nil,
        onPinchedToZoomOut: (() -> Void)? = nil
    ) {
        self.onPinchedToZoomIn = onPinchedToZoomIn
        self.onPinchedToZoomOut = onPinchedToZoomOut
    }

    func handleMagnify(
        magnification: CGFloat,
        velocity: CGFloat,
        gestureDuration: TimeInterval
    ) {
        let smoothingFactor: CGFloat = 0.3
        smoothMagnification = smoothMagnification * (1 - smoothingFactor) + magnification * smoothingFactor

        let effectiveMagnification = smoothMagnification

        let delta = effectiveMagnification - lastMagnification
        lastMagnification = effectiveMagnification

        let speedInfluence = min(abs(velocity) / 300.0, 0.8)
        let durationInfluence = min(gestureDuration / 0.3, 1.0)
        let dynamicThreshold = baseSensitivity * (1.0 - speedInfluence * 0.7 - durationInfluence * 0.3)
        let finalThreshold = max(minSensitivity, dynamicThreshold)

        accumulatedDelta = accumulatedDelta * 0.65 + delta * 1.5

        let triggerThreshold = finalThreshold * 1.6

        var newDirection = lastDirection

        if accumulatedDelta > triggerThreshold {
            newDirection = -1
            accumulatedDelta *= 0.25
        } else if accumulatedDelta < -triggerThreshold {
            newDirection = 1
            accumulatedDelta *= 0.25
        }

        if newDirection != lastDirection {
            lastDirection = newDirection
            if newDirection == -1 {
                onPinchedToZoomOut?()
            } else if newDirection == 1 {
                onPinchedToZoomIn?()
            }
        }
    }
}
