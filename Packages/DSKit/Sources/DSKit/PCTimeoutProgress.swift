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

    /// How often the bar updates while it runs.
    ///
    /// This is a *resolution*, not the countdown itself — the bar has to move smoothly, so it
    /// cannot just sleep once for the whole duration. Kept separate from `duration` so the two
    /// cannot be confused for each other.
    private static let resolution: TimeInterval = 0.05

    public init(duration: TimeInterval = 5) {
        self.duration = duration
    }

    /// Starts (or restarts) the countdown from 0.
    ///
    /// Each sleep is scheduled to land on an **absolute** point in the countdown rather than
    /// for a flat interval after the previous wake-up. The original loop slept 50 ms and then
    /// measured how long it had actually been, which quietly let every late wake-up accumulate:
    /// the countdown then took `50ms × iterations` of wall time, not `duration`, and the error
    /// compounded rather than washing out. Under load — which this app is not immune to — a
    /// 5s bar finished late by however long the main actor had been starved.
    ///
    /// Aligning to the start instant means a late wake-up costs nothing: it reads the true
    /// elapsed time, jumps to the correct fraction, and reschedules. The countdown is now as
    /// accurate as the clock it measures with.
    public func start() {
        task?.cancel()
        progress = 0
        isComplete = false
        let duration = self.duration
        let clock = ContinuousClock()
        task = Task { [weak self] in
            let start = clock.now
            // A duration shorter than the resolution should not push the first sample past the
            // end, so the interval is clamped to it.
            let interval = min(Self.resolution, duration)
            var tick: TimeInterval = 1
            while !Task.isCancelled {
                let due = start.advanced(by: .seconds(interval * tick))
                do {
                    try await Task.sleep(until: due)
                } catch {
                    // Cancellation, not a failed timer. Returning here rather than falling
                    // through to the loop condition makes `cancel()` take effect on the
                    // sleeping task itself, instead of waiting for the next wake-up to notice.
                    return
                }
                let elapsed = start.duration(to: clock.now)
                let fraction = min(1, elapsed / .seconds(duration))
                self?.progress = fraction
                if fraction >= 1 {
                    self?.isComplete = true
                    self?.onComplete?()
                    return
                }
                tick += 1
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
