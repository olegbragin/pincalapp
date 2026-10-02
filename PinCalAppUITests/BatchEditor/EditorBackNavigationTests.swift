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
            app.buttons["batch-save-button"].waitForExistence(timeout: 5),
            "Tapping a batch should open the batch editor"
        )
        return app
    }

    // MARK: - Back out of the event editor leaves the batch editor working

    /// The visible one. Back out of the event editor, then use the batch editor.
    @MainActor
    func testBackOutOfEventEditorLeavesTheBatchEditorUsable() throws {
        let app = openBatchEditor()

        // Into the event editor.
        let eventCell = app.cells.firstMatch
        XCTAssertTrue(eventCell.waitForExistence(timeout: 5), "The batch editor should list the event")
        eventCell.tap()
        XCTAssertTrue(
            app.textFields["event-name-field"].waitForExistence(timeout: 5),
            "Tapping the event should open the event editor"
        )

        // Back out of it.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)
        XCTAssertTrue(
            app.textFields["event-name-field"].waitForNonExistence(timeout: 5),
            "Back should leave the event editor"
        )
        XCTAssertTrue(
            app.buttons["batch-save-button"].waitForExistence(timeout: 5),
            "Back from the event editor should land on the batch editor, not the calendar"
        )

        // The point. An empty day in the batch editor's calendar must gain an event.
        XCTAssertFalse(
            KeyboardAvoidanceTestSupport.isDayMarked(day: emptyDay, in: app),
            "Day \(emptyDay) starts empty; label = \(KeyboardAvoidanceTestSupport.dayCell(day: emptyDay, in: app).label)"
        )

        KeyboardAvoidanceTestSupport.tapDay(day: emptyDay, in: app)

        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.isDayMarked(day: emptyDay, in: app),
            """
            After backing out of the event editor the batch editor must still work: tapping \
            day \(emptyDay) adds it to the batch. It stayed unmarked, which is what a store \
            that still thinks it is in the event editor does — `toggleDay` is refused and \
            the screen is inert.
            """
        )
    }

    // MARK: - Back out of the day list returns to the calendar

    /// Navigation only. See the note at the top: nothing is gated on `.dayList`, so this
    /// guards the Back button itself rather than a failure mode.
    @MainActor
    func testBackOutOfDayListReturnsToTheCalendar() throws {
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
