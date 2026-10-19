//
//  EditorBackNavigationTests.swift
//  PinCalAppUITests
//
//  Every screen the reducer can push owns its own Back button, and dispatches it.
//
//  ## The STR
//
//  1. Open a calendar, walk into an editor.
//  2. Press Back.
//  3. Carry on using the screen you land on.
//
//  **AB:** Back pops the `NavigationStack` without telling the store, so `state.stage` keeps
//  naming a screen that is no longer on the display. **EB:** the store hears about it, and
//  the screen you land on works.
//
//  ## Why the consequence is a dead screen, not a wrong label
//
//  `toggleDay` is the only action in the whole reducer gated on `stage == .batchEditor`.
//  So a stale stage does not mislabel anything — it makes the batch editor **inert**: the
//  user taps days to add them to the batch and nothing happens, with no error, no disabled
//  control, and nothing in the log. That is the assertion below, and it is why the bug
//  survived: the screen looks fine and does nothing.
//
//  The day-list case is included for the same class of defect but is **not** the same
//  severity: no action is gated on `.dayList`, so a stale stage there is latent — nothing
//  the user can do is refused. It is fixed for consistency, and its test guards the
//  navigation itself rather than claiming a failure mode that does not exist.
//
//  **The batch editor's inertness used to be caught the long way round** — by pushing the
//  event editor on top of it, pressing Back, and then tapping a day. That round trip is gone
//  with the event editor, so `testBackOutOfTheBatchEditorStillLeavesADayEditable` taps the day
//  immediately instead. It is the weaker of the two, and deliberately so: the long version
//  only existed to put a *different* screen on top first, and there is no second screen left.
//

import XCTest

final class EditorBackNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The seeded batch is on the **first day of the current month** (see
    /// `TestDataSeeder`), so the anchor is day 1 — not a hard-coded 10.
    private let anchorDay = 1
    private let emptyDay = 21

    @MainActor
    private func openBatchEditor() -> XCUIApplication {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.openDayBatchesList(day: anchorDay, in: app),
            "Day \(anchorDay) holds a seeded batch, so tapping it opens the day list"
        )
        let batch = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batch.waitForExistence(timeout: 5), "The seeded batch should be listed")
        batch.tap()
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 5),
            "Tapping a batch should open the batch editor"
        )
        return app
    }

    // The test that used to be here — `testBackOutOfEventEditorLeavesTheBatchEditorUsable` —
    // went with the screen: open the batch editor, tap an event, press Back, and assert the
    // batch editor still accepts a day tap. The assertion it existed to protect survives as the
    // test below, and it is renamed to say what it does rather than what it used to prove: with
    // the event editor gone there is nothing to push on top of the batch editor, so nothing
    // presses Back, and a name promising a round trip would be a lie.

    /// The assertion that test was there for: the batch editor is not inert.
    ///
    /// **Premise changed.** See the note above — the Back round trip is gone, so this is now
    /// "tap a day, and it is added". It still catches the bug in the file's header comment, which
    /// is that a `stage` which no longer names the batch editor makes the screen silently
    /// unresponsive rather than wrong-looking.
    @MainActor
    func testTheBatchEditorAcceptsADayTap() {
        let app = openBatchEditor()

        // An empty day in the batch editor's calendar must gain an event.
        XCTAssertFalse(
            KeyboardAvoidanceTestSupport.isDayMarked(day: emptyDay, in: app),
            "Day \(emptyDay) starts empty; label = \(KeyboardAvoidanceTestSupport.dayCell(day: emptyDay, in: app).label)"
        )

        KeyboardAvoidanceTestSupport.tapDay(day: emptyDay, in: app)

        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.isDayMarked(day: emptyDay, in: app),
            """
            Tapping day \(emptyDay) must add it to the batch. It stayed unmarked, which is what a \
            store whose `stage` no longer names the batch editor does — `toggleDay` is refused \
            and the screen is inert.
            """
        )
    }

    // MARK: - Back out of the day list returns to the calendar

    /// Navigation only. See the note at the top: nothing is gated on `.dayList`, so this
    /// guards the Back button itself rather than a failure mode.
    @MainActor
    func testBackOutOfDayListReturnsToTheCalendar() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.openDayBatchesList(day: anchorDay, in: app),
            "Day \(anchorDay) holds a seeded batch, so tapping it opens the day list"
        )
        XCTAssertTrue(
            app.staticTexts["Women Cycle"].waitForExistence(timeout: 5),
            "The day list should show the seeded batch"
        )

        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)

        XCTAssertTrue(
            app.buttons["add-batch-button"].waitForNonExistence(timeout: 5),
            "Back should leave the day list; 'new batch' exists only there"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: KeyboardAvoidanceTestSupport.dayIdentifier(day: anchorDay))
                .firstMatch.waitForExistence(timeout: 5),
            "Back should return to the calendar, which owns the day grid"
        )
    }
}
