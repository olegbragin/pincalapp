//
//  PCTimeoutProgress.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import Foundation
import Observation

/// Drives a linear progress value from 0 to 1 over a fixed duration and reports
/// completion. Decoupled from any view so it is testable and platform-agnostic
/// (it only depends on `Foundation`/`Observation`).
@MainActor
@Observable
public final class PCTimeoutProgress {
    public private(set) var progress: Double = 0
    public private(set) var isComplete = false

    /// Called once when the countdown reaches the end.
    public var onComplete: (() -> Void)?

    private let duration: TimeInterval
    private var task: Task<Void, Never>?

    public init(duration: TimeInterval = 5) {
        self.duration = duration
    }

    /// Starts (or restarts) the countdown from 0.
    public func start() {
        task?.cancel()
        progress = 0
        isComplete = false
        let duration = self.duration
        let startTime = Date()
        task = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let fraction = min(1, elapsed / duration)
                self?.progress = fraction
                if fraction >= 1 {
                    self?.isComplete = true
                    self?.onComplete?()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Cancels the countdown and resets progress.
    public func cancel() {
        task?.cancel()
        task = nil
        progress = 0
        isComplete = false
    }
}
