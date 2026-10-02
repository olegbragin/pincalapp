//
//  PCNameAutosaveTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 02.10.2026.
//

import Foundation
import Testing
@testable import SingleCalendarFeature

@MainActor
@Suite("PCNameAutosave")
struct PCNameAutosaveTests {

    /// Counts what actually fired, without sleeping for the delay.
    private func settled(
        _ autosave: PCNameAutosave,
        timeout: Duration = .seconds(3)
    ) async -> Int {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if autosave.hasFiredForTesting { return autosave.fireCountForTesting }
        }
        return autosave.fireCountForTesting
    }

    @Test("A single change fires once")
    func singleChangeFiresOnce() async {
        let autosave = PCNameAutosave(delay: .milliseconds(40))
        var fired = 0
        autosave.change { fired += 1 }

        _ = await settled(autosave)

        #expect(fired == 1, "one change, one write")
    }

    @Test("Bursts of changes coalesce into a single write")
    func burstsCoalesce() async {
        let autosave = PCNameAutosave(delay: .milliseconds(80))
        var fired = 0
        // Five keystrokes, each well inside the delay of the next.
        for _ in 0..<5 {
            autosave.change { fired += 1 }
            try? await Task.sleep(for: .milliseconds(10))
        }

        _ = await settled(autosave)

        #expect(fired == 1, "five keystrokes, one write — otherwise each is a full calendar rewrite")
    }

    /// The starvation case a plain trailing debounce cannot handle.
    @Test("Continuous typing still writes, bounded by maxWait")
    func continuousTypingStillWrites() async {
        let autosave = PCNameAutosave(delay: .milliseconds(60), maxWait: .milliseconds(200))
        var fired = 0

        // Changes keep arriving faster than the delay — a plain debounce would never fire,
        // and the work would not be saved until the user finally stopped.
        let deadline = ContinuousClock.now + .milliseconds(400)
        while ContinuousClock.now < deadline {
            autosave.change { fired += 1 }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(fired >= 1, "typing for 400ms with no pause still saved")
    }

    @Test("flush writes immediately, without waiting out the delay")
    func flushWritesNow() async {
        let autosave = PCNameAutosave(delay: .seconds(30))
        var fired = 0
        autosave.change { fired += 1 }

        #expect(fired == 0, "nothing has fired yet")

        autosave.flush()

        #expect(fired == 1, "flush is what keeps the last keystroke from being lost on a switch")
    }

    @Test("cancel drops pending work instead of writing it")
    func cancelDropsPendingWork() async {
        let autosave = PCNameAutosave(delay: .milliseconds(40))
        var fired = 0
        autosave.change { fired += 1 }

        autosave.cancel()
        try? await Task.sleep(for: .milliseconds(120))

        #expect(fired == 0, "a superseded write must not land")
    }

    /// The bug a naive debounce has: a newer change arriving while an older timer is already
    /// in flight lets the stale timer write the newer work early, and the ceiling fires on
    /// every keystroke.
    @Test("A timer from a superseded change does not fire early")
    func supersededTimerDoesNotFireEarly() async {
        let autosave = PCNameAutosave(delay: .milliseconds(200))
        var fired = 0

        autosave.change { fired += 1 }
        try? await Task.sleep(for: .milliseconds(20))
        autosave.change { fired += 1 }

        // Still inside the *first* change's window, but the second reset the timer.
        try? await Task.sleep(for: .milliseconds(120))
        #expect(fired == 0, "the debounce restarted rather than being cut short")

        _ = await settled(autosave)
        #expect(fired == 1, "and then it fired exactly once, for the latest change")
    }

    @Test("flush on nothing pending does nothing")
    func flushOnNothingIsHarmless() async {
        let autosave = PCNameAutosave()
        var fired = 0

        autosave.flush()

        #expect(fired == 0)
    }
}