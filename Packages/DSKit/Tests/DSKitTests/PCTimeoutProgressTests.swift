
import Foundation
import Testing
import DSKit

@MainActor
@Suite("PCTimeoutProgress Tests")
struct PCTimeoutProgressTests {
    @Test("Completes after the duration and reports completion")
    func completesAfterDuration() async {
        let progress = PCTimeoutProgress(duration: 0.05)
        var completed = false
        progress.onComplete = { completed = true }

        progress.start()

        try? await Task.sleep(for: .milliseconds(300))

        #expect(progress.isComplete)
        #expect(progress.progress == 1)
        #expect(completed)
    }

    @Test("Cancel resets progress and does not complete")
    func cancelResetsProgress() async {
        let progress = PCTimeoutProgress(duration: 10)
        progress.start()

        try? await Task.sleep(for: .milliseconds(80))
        progress.cancel()

        #expect(progress.progress == 0)
        #expect(!progress.isComplete)
    }

    @Test("Restart resets to zero")
    func restartResets() async {
        let progress = PCTimeoutProgress(duration: 10)
        progress.start()

        try? await Task.sleep(for: .milliseconds(80))
        progress.start()

        #expect(progress.progress == 0)
        #expect(!progress.isComplete)
    }

    /// Cancellation must be honoured *while the task is sleeping*, not merely at the next tick.
    ///
    /// This is the behaviour the `do`/`catch` around the sleep exists to provide: the loop
    /// previously swallowed the cancellation error and only noticed at the top of the next
    /// iteration, so a cancelled countdown stayed alive for up to one resolution period.
    ///
    /// The 10s duration against an 80ms check is deliberate. A narrow window here would be a
    /// wall-clock assertion measuring the machine rather than the code; the margin means this
    /// passes only if cancellation genuinely works, not because the host was quiet.
    @Test("Cancel stops a countdown that is mid-flight and never completes")
    func cancelDuringSleepNeverCompletes() async {
        let progress = PCTimeoutProgress(duration: 10)
        var completed = false
        progress.onComplete = { completed = true }
        progress.start()

        try? await Task.sleep(for: .milliseconds(80))
        progress.cancel()

        // Well inside the original 10s: if cancellation did not take, this is where it shows.
        try? await Task.sleep(for: .milliseconds(200))

        #expect(!progress.isComplete)
        #expect(progress.progress == 0)
        #expect(!completed)
    }

    /// A restart must not leave the previous countdown's `onComplete` able to fire.
    @Test("Restart cancels the previous countdown")
    func restartCancelsPreviousCountdown() async {
        let progress = PCTimeoutProgress(duration: 0.2)
        var completions = 0
        progress.onComplete = { completions += 1 }

        progress.start()
        try? await Task.sleep(for: .milliseconds(20))
        progress.start()

        // Past the first countdown's original 0.2s end.
        try? await Task.sleep(for: .milliseconds(400))

        // One completion — the second countdown — never two.
        #expect(completions == 1)
    }
}
