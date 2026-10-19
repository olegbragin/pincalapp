//
//  BatchEditCommitTests.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 24.08.2026.
//

import XCTest

final class BatchEditCommitTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// STR regression: edit a batch (add an event), leave the editor, go back to the
    /// calendar. The newly selected day must immediately behave as a day with
    /// events (opens the batch list, not a new-batch editor).
    /// **Premise changed.** This was "saving the batch from the editor updates the calendar",
    /// and the Save checkmark was the step under test. It no longer is: the day was added by
    /// `toggleDay`, which merged and wrote the row at the moment it was tapped. The test now
    /// leaves with Back and asserts the same visible outcome — the day holds a batch and
    /// tapping it opens the batch list rather than a new-batch editor.
    @MainActor
    func testLeavingBatchEditorUpdatesCalendarWithoutReachingRoot() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Day with an existing batch -> batch list -> batch editor.
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)

        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should show the seeded batch")
        batchRow.tap()

        // Select an additional event on an empty day inside the editor.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        // Back is the only exit now, and it is also the editor's one addressable element —
        // which is why this doubles as the "editor is open" wait.
        let editorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(editorBack.waitForExistence(timeout: 5), "Back button should be visible in the editor")
        editorBack.tap()

        // Editor dismissed back to the batch list; go back to the calendar.
        XCTAssertFalse(
            editorBack.waitForExistence(timeout: 2),
            "Editor should be dismissed after Back"
        )
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)
        // Leaving dismisses the calendar, so re-open it before tapping a day. On the iPhone
        // the calendar stayed selected and this was unnecessary, which is why it went
        // unnoticed; on the iPad the leave returns to the *list*, where there is no day cell.
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // The edited day now has events: tapping it must open the BATCH LIST,
        // not a new-batch editor. Before the fix this opened the editor because
        // the commit only ran when the navigation stack reached its root.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)
        XCTAssertTrue(
            batchRow.waitForExistence(timeout: 5),
            "Tapping the newly selected day should open the batch list with the edited batch"
        )
    }

    // Two tests used to live here, and both are gone with the screen: `testEditingExistingEvent…`
    // (open an event, check the name field is pre-filled, rename, reopen, check it persisted) and
    // `testRenamedEventPersistsWhenReopeningBatchImmediately` (the same rename, but never
    // returning to the calendar root between the two). Neither had a premise left once an event
    // row stopped opening anything — and a test whose premise is gone is worse than no test,
    // because it keeps passing while checking nothing that exists.

    // MARK: - New-batch STR regressions

    /// Exact STR regression for the reported bug:
    /// 1) Open calendar
    /// 2) Tap a day without events  -> new-batch editor
    /// 3) Enter a batch name and give it a colour
    /// 4) Leave the batch editor
    /// 5) Tap the day again
    /// EB: exactly one batch in the list. AB: two batches with the same event.
    ///
    /// **Premise changed.** This ran *through* the event editor — name the placeholder event,
    /// leave the child screen, leave the batch — because that was the only way a user touched an
    /// event at all, and the duplicate only showed up when two writers had run in sequence. The
    /// editor is gone, so the sequence is now "colour the batch, leave, come back", which still
    /// writes twice (the colour write supersedes the debounced name write) and still has to land
    /// on one row. The duplicate is the claim; the route to it is no longer available.
    @MainActor
    func testLeavingANewBatchAndReopeningItDoesNotDuplicateIt() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // 2) Tap an empty day -> new-batch editor with a placeholder event.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        // 3) Enter the batch name.
        let batchNameField = app.textFields["batch-name-field"]
        XCTAssertTrue(batchNameField.waitForExistence(timeout: 5), "Batch editor should open for the tapped day")
        KeyboardAvoidanceTestSupport.replaceText(in: batchNameField, with: "Edited Batch")

        // 3b) Give the batch a colour.
        //
        //     This used to be load-bearing in a way that no longer exists. While a Save button
        //     was on screen it was `.disabled(!canSave)`, and a day tapped on the calendar
        //     started the batch with `colorName: ""` — so without this step both Saves sat
        //     disabled, tapping them was a no-op, and the batch editor never came back.
        //     Nothing gates on it now: the write happens per edit, and `canSave` has no button
        //     to disable. Recolouring the batch still propagates to its events, so the
        //     placeholder event picks the colour up here — which is also what makes this the
        //     second writer in the sequence the bug needs.
        selectEventColor("eventColorOption2", in: app)

        // 3c) The placeholder event is listed. It is found by index rather than by its text:
        //     the row shows a formatted timestamp, and both the word inside it and the name
        //     that used to sit in front of it are gone — a text query here would be matching on
        //     the locale's date format, and also on the keyboard's "dictation" key, whose label
        //     contains "at".
        let eventRow = KeyboardAvoidanceTestSupport.eventRow(0, in: app)
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "Placeholder event row should exist in the batch editor")

        // 4) Leave the batch editor.
        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.waitForExistence(timeout: 5), "Batch editor back button should be visible")
        batchEditorBack.tap()
        XCTAssertFalse(
            batchEditorBack.waitForExistence(timeout: 2),
            "Batch editor should be dismissed after Back"
        )

        // 4a) The editor dismissed back to the calendar detail. The day we just
        //      added a batch to must now be MARKED as having events. The reported bug
        //      leaves it unmarked because the saved batch holds no events.
        let day20ID = KeyboardAvoidanceTestSupport.dayIdentifier(day: 20)
        let day20Query = app.descendants(matching: .any).matching(identifier: day20ID)
        XCTAssertTrue(day20Query.firstMatch.waitForExistence(timeout: 5), "Should be back on the calendar detail after leaving the batch editor")
        XCTAssertTrue(
            day20Query.firstMatch.label.lowercased().contains("events"),
            "Bug: day 20 is not marked as having events after the edit (label: '\(day20Query.firstMatch.label)')"
        )

        // 4b) Tap the day again. The day now has a batch, so this opens the
        //      day's batch list (the editor dismissed back to the calendar).
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        // The day now has exactly ONE batch, not two with the same name and
        // event (the reported bug).
        let batchNameMatches = app.staticTexts.matching(NSPredicate(format: "label == %@", "Edited Batch"))
        XCTAssertTrue(batchNameMatches.firstMatch.waitForExistence(timeout: 5), "The day's batch list should show the new batch")

        // Let a delayed duplicate (if any) surface before counting.
        let settleDeadline = Date().addingTimeInterval(3)
        while Date() < settleDeadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertEqual(
            batchNameMatches.count,
            1,
            "Bug: leaving the batch then reopening it created \(batchNameMatches.count) batches with the same event instead of one"
        )

        // 5) Reopen the batch. It must still contain its event — the reported
        //    bug opens the batch editor with an EMPTY event list.
        batchNameMatches.firstMatch.tap()
        let eventInBatch = KeyboardAvoidanceTestSupport.eventRow(0, in: app)
        XCTAssertTrue(
            eventInBatch.waitForExistence(timeout: 5),
            "Bug: the saved batch opened with an EMPTY event list — the event was lost"
        )
    }

    // MARK: - Color change regressions (same STR as name, but changing color)

    @MainActor
    private func selectEventColor(_ colorName: String, in app: XCUIApplication) {
        // The implementation lives in the shared support enum: it is the same picker, the
        // same sheet, and the same "topmost hittable, because two editors can be mounted at
        // once" problem as every other colour assertion in the UI suite.
        KeyboardAvoidanceTestSupport.selectColor(colorName, in: app)
    }

    /// Changing the batch color (which is applied to, and rewrites, every event
    /// in the batch) must persist after leaving the batch editor and a calendar round-trip.
    @MainActor
    func testChangingEventColorPersistsAfterLeavingBatchEditor() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        // The batch editor exposes the batch color picker. The batch color is
        // the source of truth and rewrites every event's color in the batch.
        let picker = app.buttons["color-picker-compact"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption1", "Initial batch color should be option1")

        selectEventColor("eventColorOption2", in: app)

        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.waitForExistence(timeout: 5))
        batchEditorBack.tap()

        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)
        // Leaving dismisses the calendar, so re-open it before tapping a day. On the iPhone
        // the calendar stayed selected and this was unnecessary, which is why it went
        // unnoticed; on the iPad the leave returns to the *list*, where there is no day cell.
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        // The event is still there, and it is still in the recoloured batch.
        //
        // The assertion used to be read off the *event* editor's own picker, reached by tapping
        // the row and coming back. That round trip is gone with the editor — the batch editor is
        // now the only place a colour is chosen — so the round trip is read here, where the
        // colour actually lives, and the row's presence is the check that the event survived.
        let reopenedEventRow = KeyboardAvoidanceTestSupport.eventRow(0, in: app)
        XCTAssertTrue(reopenedEventRow.waitForExistence(timeout: 5))

        XCTAssertTrue(picker.waitForExistence(timeout: 5), "The batch editor's own picker is the only one left")
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption2", "Persisted color must be option2 after save and reopen via calendar")
    }

    /// Changing the batch color must also persist when reopening batch immediately without returning to calendar root.
    @MainActor
    func testChangingEventColorPersistsWhenReopeningBatchImmediately() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        let picker = app.buttons["color-picker-compact"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption1")

        selectEventColor("eventColorOption3", in: app)

        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.waitForExistence(timeout: 5))
        batchEditorBack.tap()
        XCTAssertFalse(batchEditorBack.waitForExistence(timeout: 2), "Batch editor should be dismissed after Back")
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))

        batchRow.tap()

        let reopenedEventRow = KeyboardAvoidanceTestSupport.eventRow(0, in: app)
        XCTAssertTrue(reopenedEventRow.waitForExistence(timeout: 5))

        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption3", "Persisted color must be option3 after immediate reopen")
    }

    /// STR: deleting an event from the batch editor's events list must also
    /// unmark the corresponding day in the calendar shown at the top.
    @MainActor
    func testDeletingEventFromBatchListUnmarksCalendar() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 5),
            "Batch editor should open"
        )

        // The batch editor's calendar marks days that have events.
        let day1ID = KeyboardAvoidanceTestSupport.dayIdentifier(day: 1)
        let day2ID = KeyboardAvoidanceTestSupport.dayIdentifier(day: 2)
        let day1Query = app.descendants(matching: .any).matching(identifier: day1ID)
        let day2Query = app.descendants(matching: .any).matching(identifier: day2ID)
        XCTAssertTrue(day1Query.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(day2Query.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(day1Query.firstMatch.label.lowercased().contains("events"), "Day 1 should be marked")
        XCTAssertTrue(day2Query.firstMatch.label.lowercased().contains("events"), "Day 2 should be marked")

        // Delete the first event row (day 1, first in the date-sorted list).
        let deleteEvent = app.buttons["Delete event"].firstMatch
        XCTAssertTrue(deleteEvent.waitForExistence(timeout: 5), "Event delete button should exist")
        deleteEvent.tap()

        // Day 1 must now be unmarked in the calendar.
        let deadline = Date().addingTimeInterval(5)
        var day1Marked = true
        while Date() < deadline {
            if day1Query.firstMatch.exists,
               !day1Query.firstMatch.label.lowercased().contains("events")
            {
                day1Marked = false
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(
            day1Marked,
            "Day 1 should be unmarked after its event was deleted"
        )
    }
}
