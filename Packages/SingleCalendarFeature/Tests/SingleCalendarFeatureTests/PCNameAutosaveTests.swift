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
            if autosave.hasFiredForTesting {
                return autosave.fireCountForTesting
            }
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
    ///
    /// The loop runs *until* the write lands rather than for a fixed window, and typing is still
    /// going when it does. Both halves matter. A fixed window measured how much wall clock the
    /// machine gave us: with `maxWait` at 200ms inside a 400ms loop, four parallel clones were
    /// enough for the main actor to be starved past the deadline, and the test failed having
    /// asserted nothing about the autosave. And if the loop simply *stopped* and then waited, the
    /// trailing debounce would satisfy the assertion on its own 60ms later — a different property
    /// entirely, and one that would have passed with the ceiling deleted.
    ///
    /// `delay` and `maxWait` are an order of magnitude apart for the same reason. Both timers are
    /// wall-clock and both are delayed by load, so the only thing keeping this honest is there
    /// being far too little quiet for the trailing debounce to take: a stall big enough for a
    /// 500ms debounce to beat a 50ms ceiling is a stall this test should fail on, not absorb.
    @Test("Continuous typing still writes, bounded by maxWait")
    func continuousTypingStillWrites() async {
        let autosave = PCNameAutosave(delay: .milliseconds(500), maxWait: .milliseconds(50))
        var fired = 0

        // A guard against hanging forever, not the thing under test: the premise is that steady
        // typing cannot starve the write indefinitely, so the loop's exit condition *is* the
        // write happening.
        let cap = ContinuousClock.now + .seconds(5)
        while fired == 0, ContinuousClock.now < cap {
            autosave.change { fired += 1 }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(fired >= 1, "typing with no pause still saved")
    }

    @Test("flush writes immediately, without waiting out the delay")
    func flushWritesNow() {
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
    func flushOnNothingIsHarmless() {
        let autosave = PCNameAutosave()
        var fired = 0
        autosave.change { fired += 1 }
        autosave.cancel() // the only way back to "nothing pending" without waiting

        autosave.flush()

        // The counter used to be declared and never wired, so this asserted a variable the
        // test itself had not changed — it could not fail. `fire` does run on a bare `flush`
        // (`fireCountForTesting` is bumped before the `pending` check), so the thing that has
        // to be true is that no write was *performed*, not that nothing happened internally.
        #expect(fired == 0, "and no write is issued")
    }

    @Test("flush on a fresh autosave performs no write")
    func flushWithNoChangeAtAllIsHarmless() {
        let autosave = PCNameAutosave()
        var fired = 0
        autosave.change { fired += 1 }

        autosave.flush()

        #expect(fired == 1, "the one change that was pending is written")
    }
}
