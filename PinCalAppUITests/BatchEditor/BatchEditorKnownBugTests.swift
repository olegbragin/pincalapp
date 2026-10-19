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

        // §16.1 step 3 — name the batch and colour it.
        // A colour was required at every save: a batch staged from a day tap had
        // `colorName: ""` and an uncoloured batch's Save was disabled. It gates nothing now.
        //
        // This step used to go on into the batch's event and name that too, through the child
        // editor, and the assertions at the tail leaned on that: they identified the surviving
        // event by being the only *named* one. There is no way to name an event any more, so the
        // tail reads the day markers and the row count instead — which is what the bug is
        // actually about, and what §16.3's two hypotheses actually distinguish.
        //
        // **Colour before name**, as everywhere else. Typing raises the keyboard, the keyboard
        // covers the editor's first row, and the picker is in that row — so picking first means
        // no keyboard is up yet. The name follows, and it is the last thing typed precisely
        // because typing is what raises the keyboard. See `selectColor`.
        KeyboardAvoidanceTestSupport.selectColor("eventColorOption1", in: app)
        KeyboardAvoidanceTestSupport.replaceText(in: nameField, with: batchName)

        // By index: a row's text is a formatted timestamp, whose wording is the locale's.
        let placeholderRow = KeyboardAvoidanceTestSupport.eventRow(0, in: app)
        XCTAssertTrue(placeholderRow.waitForExistence(timeout: 5), "The batch should list its placeholder event")

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
        // Every one of the four days is marked, on both mounted calendars — the editor's and
        // the one underneath the sheet.
        //
        // **Premise changed.** This used to count the editor's rows. `List` is lazy and
        // realizes only what is on screen, so that counted *rows visible*, not events held:
        // the batch editor gained a time picker under the name field, the fourth row stopped
        // fitting above the fold, and the assertion began reporting a batch of three for a
        // batch of four — with all four days marked on screen at that exact moment. Counting
        // the markers measures the thing the test is about, and is unaffected by how tall the
        // editor is.
        for day in [anchorDay] + addedDays {
            assertMarked(day, in: app, line: #line + 1)
        }

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

        // The surviving event is the one on the day that was *kept*, and every event here is a
        // placeholder. `toggling` appends `Self.placeholder(on:colorName:)` for a day it turns
        // on, and with the event editor gone there is no way to name one — so "exactly one event
        // row, and it is the surviving day's" is the whole of the claim.
        //
        // **Premise changed, twice.** Both of these used to be text queries — one counting rows
        // whose label contained "at", one asserting the name "Named" was gone. A card's row now
        // shows a formatted timestamp and *no name at all*, so the second assertion could not
        // fail: the string it looks for is not on the screen anywhere. Rows are counted by
        // identifier instead, which is the only handle that survives a label the locale decides.
        let eventRows = KeyboardAvoidanceTestSupport.cardEventRows(in: app)
        XCTAssertEqual(
            eventRows.count, 1,
            "the card must show exactly one event row; found \(eventRows.allElementsBoundByIndex.map(\.label))"
        )
    }

    /// How many events the batch editor is listing.
    ///
    /// Counts only what the lazy `List` has realized, so it is a floor and not the batch's
    /// size — which is why §16.1's sanity check above asserts on day markers instead. It
    /// survives here because the assertion that uses it is about a batch that has been
    /// reduced to a single event, which fits on screen by a wide margin.
    @MainActor
    private func eventRowCount(in app: XCUIApplication) -> Int {
        KeyboardAvoidanceTestSupport.eventRowCount(in: app)
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
