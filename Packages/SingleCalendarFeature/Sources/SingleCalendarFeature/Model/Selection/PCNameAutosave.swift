//
//  PCNameAutosave.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 02.10.2026.
//

import Foundation

/// Coalesces rapid name edits into one write, with a ceiling on how long an edit may wait.
///
/// Two rules, and the second is not optional.
///
/// **Trailing.** The write fires once typing pauses, not on every keystroke. A batch name is
/// free text, so a user typing "Swimming" produces five changes; five writes would mean five
/// `saveCalendar` calls, each of which re-reads and rewrites the whole calendar because it is
/// read-modify-write with a delete of everything absent from the incoming set.
///
/// **`maxWait`,** because a plain trailing debounce never fires at all if changes keep
/// arriving faster than the delay. Someone typing steadily for two minutes would save
/// nothing until they finally stopped, and stopping is not something the app can assume. The
/// ceiling is measured from the first change in a run, so it is a bound on how long any edit
/// waits rather than a second debounce that resets on every keystroke.
///
/// A class, not a struct: the timer closures capture it, and a struct would be copied into
/// each of them — so `fire` would mutate temporaries and the pending work would be lost. It
/// is main-actor isolated because it belongs to the store, which is, and because the write it
/// schedules has to be issued from there anyway.
@MainActor
public final class PCNameAutosave {

    // MARK: - Properties

    /// The quiet period production uses.
    ///
    /// 250 ms sits below the ~300 ms where debounce starts to feel as lag, and above nothing
    /// that matters: the write is local and sub-millisecond, so a shorter wait would buy no
    /// speed and only risk firing mid-keystroke.
    public static let defaultDelay: Duration = .milliseconds(250)

    /// The ceiling production uses.
    public static let defaultMaxWait: Duration = .seconds(5)

    /// Quiet period before a write.
    public var delay: Duration = PCNameAutosave.defaultDelay

    /// Longest any single change may wait, however fast the typing.
    public var maxWait: Duration = PCNameAutosave.defaultMaxWait

    /// How many times `fire` has run. Test-only, so a test can wait on the condition rather
    /// than on a sleep — the timers are scheduler-driven, so a fixed wait is a flake.
    public private(set) var fireCountForTesting = 0

    /// Whether anything has fired yet, for the same reason.
    public var hasFiredForTesting: Bool { fireCountForTesting > 0 }

    private var pending: (@MainActor () -> Void)?
    private var timer: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?

    /// Distinguishes this run from the next. A timer that fires just after a newer `change`
    /// has already rescheduled must not write the newer work early, or the debounce becomes
    /// meaningless and the ceiling fires on every keystroke.
    private var runID: UInt64 = 0

    // MARK: - Init

    public init(
        delay: Duration = PCNameAutosave.defaultDelay,
        maxWait: Duration = PCNameAutosave.defaultMaxWait
    ) {
        self.delay = delay
        self.maxWait = maxWait
    }

    // MARK: - Methods

    /// Fires `write` once typing settles. Call on every change.
    ///
    /// `write` is expected to enqueue, not to perform: it runs on the main actor and should
    /// return immediately so that a slow write cannot delay the next keystroke.
    func change(_ write: @escaping @MainActor () -> Void) {
        runID &+= 1
        let current = runID

        pending = write

        // Cancel whatever was scheduled. A new change makes the previous timer irrelevant
        // whether or not it had already fired — the work is captured in `pending`, and the
        // `runID` check stops a timer that was already in flight from writing stale work.
        timer?.cancel()
        timer = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            fire(expectedRun: current)
        }

        if deadlineTask == nil {
            deadlineTask = Task { [maxWait] in
                try? await Task.sleep(for: maxWait)
                guard !Task.isCancelled else { return }
                fire(expectedRun: nil)
            }
        }
    }

    /// Writes immediately if anything is waiting.
    ///
    /// Called when leaving the calendar, so the last thing typed is not the one thing lost.
    func flush() {
        timer?.cancel()
        timer = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        fire(expectedRun: nil)
    }

    /// Drops any pending write without performing it.
    func cancel() {
        timer?.cancel()
        timer = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        runID &+= 1
        pending = nil
    }

    /// `expectedRun` of `nil` means "fire regardless" — used by `flush` and the ceiling,
    /// which are not tied to a particular scheduled timer.
    private func fire(expectedRun: UInt64?) {
        if let expectedRun, expectedRun != runID { return }
        timer?.cancel()
        timer = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        fireCountForTesting &+= 1
        guard let pending else { return }
        self.pending = nil
        pending()
    }
}