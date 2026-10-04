//
//  BatchEditorKnownBugTests.swift
//  PinCalAppUITests
//
//  REFACTOR_PLAN.md §16 — the reported bug, encoded step for step.
//
//  §16.4 requires this test to **fail on the current code first**. It does; see the
//  comment on the final assertion. The diagnostic assertions in the middle are not
//  decoration: §16.3 hypothesis 1 says the symptom to distinguish is "does the editor
//  still show the surviving event when the editor is left, or is it already gone", and that
//  is exactly the question these answer.
//
//  The STR in §16.1 names Oct 4/5/6/7. The seeded calendar is built for the *current*
//  month, so the days are renumbered to four consecutive empty ones — 14, 15, 16, 17 —
//  with the same shape: one anchor, three added, then the anchor and two of the added
//  removed, leaving one.
//

import XCTest

final class BatchEditorKnownBugTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The day the batch is created on — §16.1 step 2's "a day that has no events".
    private let anchorDay = 14
    /// §16.1 step 4's additions, so the batch holds four days on save.
    private let addedDays = [15, 16, 17]
    /// §16.1 step 6's removals. The survivor is the last added day, 17.
    private let survivingDay = 17

    private let batchName = "Window"

    @MainActor
    func testRemovingThreeOfFourDaysLeavesTheBatchWithTheFourth() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // §16.1 step 2 — tap an empty day, which opens the editor for a new batch.
        KeyboardAvoidanceTestSupport.tapDay(day: anchorDay, in: app)

        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open for the anchor day")

        // §16.1 step 3 — name the batch, then go into its event and name that.
        // A colour was required at every save: a batch staged from a day tap had
        // `colorName: ""` and an uncoloured batch's Save was disabled. It gates nothing now.
        KeyboardAvoidanceTestSupport.replaceText(in: nameField, with: batchName)
        KeyboardAvoidanceTestSupport.selectColor("eventColorOption1", in: app)

        let placeholderRow = app.collectionViews.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "at"))
            .firstMatch
        XCTAssertTrue(placeholderRow.waitForExistence(timeout: 5), "The batch should list its placeholder event")
        placeholderRow.tap()

        let eventNameField = app.textFields["event-name-field"]
        XCTAssertTrue(eventNameField.waitForExistence(timeout: 5), "Event editor should open")
        KeyboardAvoidanceTestSupport.replaceText(in: eventNameField, with: "Named")
        // The event editor's Back. Its Save checkmark is gone; the rename reached the batch on
        // the keystroke, so leaving loses nothing.
        let eventEditorBack = app.buttons["event-editor-back-button"]
        XCTAssertTrue(eventEditorBack.isEnabled, "The event editor must be leaveable")
        eventEditorBack.tap()
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 5),
            "Back in the batch editor after leaving the event editor"
        )

        // §16.1 step 4 — add the other three days, then leave.
        for day in addedDays {
            KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)
        }
        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.isEnabled, "The batch editor must be leaveable")
        batchEditorBack.tap()
        XCTAssertTrue(batchEditorBack.waitForNonExistence(timeout: 3), "Batch editor should dismiss after Back")

        // Already back on the calendar, with no back tap in between: the anchor day was
        // empty, so `dayTappedInCalendar` pushed the editor *from the calendar* rather than
        // from a day list, and leaving popped that one level. (A batch opened from a day
        // list pops back to the day list instead, which is why
        // `testBatchListStillShowsBatchAfterRemovingAnchorDay` does need a back tap here.)

        // §16.1 step 5 — back on the calendar, tap the surviving day, open the batch.
        KeyboardAvoidanceTestSupport.tapDay(day: survivingDay, in: app)
        let card = app.staticTexts[batchName]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "The batch list should show the batch")
        card.tap()
        XCTAssertTrue(batchEditorBack.waitForExistence(timeout: 5), "The batch editor should open")

        // Sanity: the batch really did hold all four days before we remove any. If this
        // ever fails, steps 4 or the day taps moved and nothing below is about the bug.
        XCTAssertEqual(eventRowCount(in: app), 4, "The batch should hold four events before the removals")

        // §16.1 step 6 — remove the anchor and the first two added days, leaving one.
        for day in [anchorDay] + Array(addedDays.dropLast()) {
            KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)
        }

        // §16.3 hypothesis 1's diagnostic, asked directly. The report is that the list comes
        // back empty; that has two quite different causes — the removals took an event they
        // should not have, or they were fine and the save treated the batch as a delete
        // because it looked empty. The count before leaving tells them apart, and it is
        // asserted rather than printed so a regression is a failure and not a log line.
        XCTAssertEqual(
            eventRowCount(in: app), 1,
            "After removing three of four days the editor must still hold the surviving one.\n"
                + "     If this is the assertion that fails, the removal path is the bug (§16.3 hypothesis 1). "
                + "If it passes and the assertion below fails, the save treated a non-empty batch as a delete."
        )

        // …and *which* one survived. "The list came back empty" is also what you see if the
        // removals were correct but took the wrong three days and left a batch that no
        // longer touches day 17. The markers in the editor's own calendar say so directly,
        // and they are read across every mounted match because the main calendar behind
        // exposes the same day identifiers.
        assertMarked(survivingDay, in: app, line: #line + 1)
        for day in [anchorDay] + Array(addedDays.dropLast()) {
            assertUnmarked(day, in: app, line: #line + 1)
        }

        batchEditorBack.tap()
        XCTAssertTrue(batchEditorBack.waitForNonExistence(timeout: 3), "Batch editor should dismiss after Back")

        // No marker check here. The save pops to the day list, which covers the calendar, and
        // a day cell that is not in the accessibility tree is indistinguishable from one
        // that is unmarked — so asserting on markers at this point would be measuring the
        // wrong thing. The card below is the real observation.

        // §16.1 — EB. The batch list for the surviving day holds exactly one batch with
        // exactly one event. AB, as reported, is an empty list.
        let survivingCard = app.staticTexts[batchName]
        XCTAssertTrue(
            survivingCard.waitForExistence(timeout: 5),
            "AB reproduced: the batch list is empty after removing three of the batch's four days"
        )
        XCTAssertEqual(
            app.staticTexts.matching(identifier: batchName).count, 1,
            "The list must hold exactly one batch, not zero and not two"
        )

        // The surviving event is the one on the day that was *kept* — and it is a
        // placeholder, not the event that was named. `toggling` appends
        // `Self.placeholder(on:colorName:)` for a day it turns on, so the events added in
        // step 4 have empty names. The only named event is the anchor's, and the anchor was
        // one of the three removed — so "Named" must be gone, and exactly one unnamed event
        // row must be left.
        let eventRows = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "at"))
        XCTAssertEqual(
            eventRows.count, 1,
            "the card must show exactly one event row; found \(eventRows.allElementsBoundByIndex.map(\.label))"
        )
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Named")).count, 0,
            "the named event was on the anchor day, which was removed, so it must not survive"
        )
    }

    /// Event rows in the batch editor's list.
    ///
    /// Scoped to `collectionViews` on purpose: a global `app.buttons` search also matches
    /// the keyboard's dictation key, whose label contains "at".
    @MainActor
    private func eventRowCount(in app: XCUIApplication) -> Int {
        app.collectionViews.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "at"))
            .count
    }

    /// Whether a day is marked as holding events, across every mounted calendar cell.
    ///
    /// Both the main calendar and the batch editor's emit the same `day-MM-YYYY`
    /// identifier, so "any existing match is marked" is the question worth asking — and both
    /// panels are projected from the same payload, so they must agree.
    ///
    /// A day with no cell on screen is reported as a **failure**, not as "unmarked". A pushed
    /// screen can cover the calendar so thoroughly that its cells are not in the tree at all,
    /// and conflating that with "unmarked" turns a missing cell into a confident "the bug is
    /// not here" — which is precisely the mistake this test's first version made.
    @MainActor
    private func assertMarked(_ day: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let present = app.descendants(matching: .any)
            .matching(identifier: KeyboardAvoidanceTestSupport.dayIdentifier(day: day))
            .allElementsBoundByIndex
            .filter(\.exists)
        XCTAssertFalse(present.isEmpty, "day \(day) has no cell on screen, so 'is it marked' cannot be asked", file: file, line: line)
        XCTAssertTrue(
            present.contains { $0.label.lowercased().contains("event") },
            "day \(day) should be marked; labels = \(present.map(\.label))",
            file: file, line: line
        )
    }

    /// The inverse, with the same insistence that a cell exists to be judged.
    @MainActor
    private func assertUnmarked(_ day: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let present = app.descendants(matching: .any)
            .matching(identifier: KeyboardAvoidanceTestSupport.dayIdentifier(day: day))
            .allElementsBoundByIndex
            .filter(\.exists)
        XCTAssertFalse(present.isEmpty, "day \(day) has no cell on screen, so 'is it unmarked' cannot be asked", file: file, line: line)
        XCTAssertFalse(
            present.contains { $0.label.lowercased().contains("event") },
            "day \(day) should be unmarked; labels = \(present.map(\.label))",
            file: file, line: line
        )
    }
}
