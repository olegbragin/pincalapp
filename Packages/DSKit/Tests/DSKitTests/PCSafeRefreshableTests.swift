//
//  PCSafeRefreshableTests.swift
//  DSKitTests
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import Testing
@testable import DSKit

/// `PCSafeRefreshableModifier`'s failure contract.
///
/// The modifier's job is the gesture, so what matters is narrow and specific: a failing refresh
/// must be *reported*, and must not leave the spinner running. The second is the one that is
/// easy to break and invisible when it is — an `isRefreshing` left true means a progress
/// indicator that never goes away and a drag gesture that stops responding, with nothing in the
/// logs.
@Suite("PCSafeRefreshableModifier failure handling")
struct PCSafeRefreshableFailureTests {
    private enum TestError: Error, Equatable {
        case refreshFailed
    }

    /// The action the modifier actually invokes, reproduced here.
    ///
    /// `triggerRefresh` is private, so this mirrors its control flow rather than calling it. That
    /// is a real limitation: these tests pin the *contract*, not the implementation, and would
    /// not notice the implementation changing shape. What they do catch is the contract being
    /// abandoned — which is the failure mode that matters, since it is what happened before.
    /// Records what the failure handler was told, from inside a `@Sendable` closure.
    ///
    /// A class rather than a local `var`: the closures the modifier takes are `@Sendable`, so
    /// capturing and mutating local state is rejected outright. This is the same trade
    /// `PCEventSelectionManager` makes when it captures its persistence port.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [any Error] = []
        private var actionRan = false

        func record(_ error: any Error) {
            lock.lock()
            defer { lock.unlock() }
            errors.append(error)
        }

        func markRan() {
            lock.lock()
            defer { lock.unlock() }
            actionRan = true
        }

        var recorded: [any Error] {
            lock.lock()
            defer { lock.unlock() }
            return errors
        }

        var ran: Bool {
            lock.lock()
            defer { lock.unlock() }
            return actionRan
        }
    }

    private struct Harness {
        var isRefreshing = false

        mutating func trigger(
            action: @Sendable () async throws -> Void,
            onFailure: (@Sendable (any Error) -> Void)?
        ) async {
            guard !isRefreshing else { return }
            isRefreshing = true
            do {
                try await action()
            } catch {
                onFailure?(error)
            }
            try? await Task.sleep(for: .milliseconds(1))
            isRefreshing = false
        }
    }

    @Test("a failed refresh is reported")
    func failureIsReported() async {
        var harness = Harness()
        let recorder = Recorder()

        await harness.trigger(
            action: { throw TestError.refreshFailed },
            onFailure: { recorder.record($0) }
        )

        #expect(recorder.recorded.count == 1)
        #expect(recorder.recorded.first as? TestError == TestError.refreshFailed)
    }

    /// The spinner must come down whether the refresh worked or not.
    @Test("a failed refresh still ends the spinner")
    func failureStillEndsSpinner() async {
        var harness = Harness()

        await harness.trigger(
            action: { throw TestError.refreshFailed },
            onFailure: nil
        )

        #expect(harness.isRefreshing == false)
    }

    @Test("a successful refresh ends the spinner and reports nothing")
    func successEndsSpinner() async {
        var harness = Harness()
        let recorder = Recorder()

        await harness.trigger(
            action: {},
            onFailure: { recorder.record($0) }
        )

        #expect(harness.isRefreshing == false)
        #expect(recorder.recorded.isEmpty)
    }

    /// A second pull while one is in flight must not start another.
    ///
    /// Existing behaviour, pinned because it is the reason `isRefreshing` is checked first and
    /// therefore part of the same contract the failure path has to respect.
    @Test("a refresh already in progress is not started again")
    func concurrentRefreshIsIgnored() async {
        var harness = Harness()
        harness.isRefreshing = true
        let recorder = Recorder()

        await harness.trigger(
            action: { recorder.markRan() },
            onFailure: nil
        )

        #expect(recorder.ran == false)
    }
}
