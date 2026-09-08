import Testing
import Foundation
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
}
