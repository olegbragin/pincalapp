//
//  PCPinchToZoomGestureModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 26.03.2026.
//

import Foundation
import Observation

@Observable
public final class PCPinchToZoomGestureModel {
    private enum Direction {
        case idle
        case zoomIn
        case zoomOut
    }

    private let baseSensitivity: CGFloat = 0.12
    private let minSensitivity: CGFloat = 0.08
    private var smoothMagnification: CGFloat = 1.0
    private var accumulatedDelta: CGFloat = 0.0
    private var lastMagnification: CGFloat = 1.0
    private var lastDirection: Direction = .idle

    public var onPinchedToZoomIn: (() -> Void)?
    public var onPinchedToZoomOut: (() -> Void)?

    public init(
        onPinchedToZoomIn: (() -> Void)? = nil,
        onPinchedToZoomOut: (() -> Void)? = nil
    ) {
        self.onPinchedToZoomIn = onPinchedToZoomIn
        self.onPinchedToZoomOut = onPinchedToZoomOut
    }

    public func handleMagnify(
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
            newDirection = .zoomOut
            accumulatedDelta *= 0.25
        } else if accumulatedDelta < -triggerThreshold {
            newDirection = .zoomIn
            accumulatedDelta *= 0.25
        }

        if newDirection != lastDirection {
            lastDirection = newDirection
            switch newDirection {
            case .zoomOut:
                onPinchedToZoomOut?()
            case .zoomIn:
                onPinchedToZoomIn?()
            case .idle:
                break
            }
        }
    }
}