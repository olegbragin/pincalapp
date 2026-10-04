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

    /// STR regression: opening an existing event inside the batch editor must
    /// pre-fill the event name.  Saving the event then the batch must persist
    /// the change so that reopening the same event shows the updated name.
    @MainActor
    func testEditingExistingEventShowsPreFilledNameAndPersistsChanges() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Day 1 of the current month has an existing batch with "Event1".
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)

        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should show the seeded batch")
        batchRow.tap()

        // Tap the first event row inside the batch editor.
        let eventRow = app.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "Event1"))
            .firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "Event row should exist in the batch editor")
        eventRow.tap()

        // The event editor must show the existing name, not an empty field.
        let nameField = app.textFields["event-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Event editor should open")
        let prefilledName = nameField.value as? String ?? ""
        XCTAssertEqual(prefilledName, "Event1", "Event name field must be pre-filled with the existing name")

        // Append text and leave. The rename reached the batch on the keystroke, not on the way out.
        nameField.tap()
        nameField.typeText("Renamed")
        // The event editor's Back. Its Save checkmark is gone, and an identifier is what makes
        // this unambiguous — the main calendar's multi-select confirm is *also* labelled "Save".
        let eventEditorBack = app.buttons["event-editor-back-button"]
        XCTAssertTrue(eventEditorBack.waitForExistence(timeout: 3), "Event editor back button should be visible")
        eventEditorBack.tap()

        // Back in the batch editor — the rename is already in it.
        let editorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(editorBack.waitForExistence(timeout: 5), "Batch editor back button should be visible after leaving the event editor")
        editorBack.tap()

        // Dismiss back to the calendar.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)

        // Re-open the same batch: tap day 1 again.
        // Leaving dismisses the calendar, so re-open it before tapping a day.
        // On the iPhone the calendar stayed selected and this was not needed, which is
        // why it went unnoticed; on the iPad the leave returns to the *list* and there is
        // no day cell to tap.
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should appear again")
        batchRow.tap()

        // Tap the event row again.
        let renamedRow = app.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "Renamed"))
            .firstMatch
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 5), "Event should now show the renamed label")
        renamedRow.tap()

        // Verify the persisted name is shown.
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Event editor should open for renamed event")
        let persistedName = nameField.value as? String ?? ""
        XCTAssertEqual(persistedName, "Event1Renamed", "Event name must persist after leaving and reopening")
    }

    /// STR regression for the reported bug:
    /// 1) Open calendar -> tap day with batch -> batch list
    /// 2) Tap batch -> batch editor
    /// 3) Tap event -> event editor
    /// 4) Change name, leave the event editor
    /// 5) Leave the batch editor -> back to batch list
    /// 6) Tap same batch again
    /// AB was old name; EB is renamed name persists without ever returning to the calendar root.
    @MainActor
    func testRenamedEventPersistsWhenReopeningBatchImmediately() {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Day 1 -> batch list -> batch editor
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should show seeded batch")
        batchRow.tap()

        // Inside batch editor, tap event row
        let eventRow = app.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "Event1"))
            .firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "Event row should exist in batch editor")
        eventRow.tap()

        // Rename in event editor
        let nameField = app.textFields["event-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Event editor should open")
        XCTAssertEqual(nameField.value as? String ?? "", "Event1")
        nameField.tap()
        nameField.typeText("Renamed")
        let eventEditorBack = app.buttons["event-editor-back-button"]
        XCTAssertTrue(eventEditorBack.waitForExistence(timeout: 3))
        eventEditorBack.tap()

        // Back in the batch editor -> leave it for the batch list.
        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.waitForExistence(timeout: 5), "Batch editor Back should be visible after leaving the event editor")
        batchEditorBack.tap()
        XCTAssertFalse(
            batchEditorBack.waitForExistence(timeout: 2),
            "Batch editor should be dismissed after Back"
        )

        // Should be back at batch list, without navigating to calendar
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Should be back at batch list after leaving the batch editor")

        // Re-open same batch immediately (no tap on calendar day, no root)
        batchRow.tap()

        // The event row must now show the renamed label
        let renamedRow = app.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "Renamed"))
            .firstMatch
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 5), "Event should show renamed label after immediate reopen")

        renamedRow.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Event editor should open for renamed event")
        let persisted = nameField.value as? String ?? ""
        XCTAssertEqual(persisted, "Event1Renamed", "Persisted name must equal edited name after immediate reopen")
    }

    // MARK: - New-batch STR regressions

    /// Exact STR regression for the reported bug:
    /// 1) Open calendar
    /// 2) Tap a day without events  -> new-batch editor
    /// 3) Enter a batch name
    /// 4) Tap the event in the list -> event editor
    /// 5) Enter an event name
    /// 6) Leave the event editor -> the batch already holds the edit
    /// 7) Leave the batch editor
    /// 8) Tap the day again
    /// EB: exactly one batch in the list. AB: two batches with the same event.
    @MainActor
    func testSavingEventThenSavingNewBatchDoesNotDuplicateIt() {
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
        //     placeholder event picks the colour up here.
        selectEventColor("eventColorOption2", in: app)

        // 4) Tap the placeholder event row -> event editor. The query must be
        //    scoped to the events collection: a global `app.buttons` search also
        //    matches the keyboard's "dictation" key (its label contains "at").
        let eventRow = app.collectionViews.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "at"))
            .firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "Placeholder event row should exist in the batch editor")
        _ = KeyboardAvoidanceTestSupport.stableFrame(of: eventRow, timeout: 4)
        eventRow.tap()

        // 5) Enter the event name.
        let eventNameField = app.textFields["event-name-field"]
        XCTAssertTrue(eventNameField.waitForExistence(timeout: 5), "Event editor should open")
        if let currentName = eventNameField.value as? String, !currentName.isEmpty {
            eventNameField.tap()
            eventNameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentName.count))
        }
        eventNameField.tap()
        eventNameField.typeText("Edited Event")

        // 6) Leave the event editor (the batch was written by the keystroke).
        let eventEditorBack = app.buttons["event-editor-back-button"]
        XCTAssertTrue(eventEditorBack.waitForExistence(timeout: 5), "Event editor back button should be visible")
        eventEditorBack.tap()

        // 7) Leave the batch editor.
        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.waitForExistence(timeout: 5), "Back in the batch editor after leaving the event editor")
        batchEditorBack.tap()
        XCTAssertFalse(
            batchEditorBack.waitForExistence(timeout: 2),
            "Batch editor should be dismissed after Back"
        )

        // 8a) The editor dismissed back to the calendar detail. The day we just
        //     added a batch to must now be MARKED as having events. The reported bug
        //     leaves it unmarked because the saved batch holds no events.
        let day20ID = KeyboardAvoidanceTestSupport.dayIdentifier(day: 20)
        let day20Query = app.descendants(matching: .any).matching(identifier: day20ID)
        XCTAssertTrue(day20Query.firstMatch.waitForExistence(timeout: 5), "Should be back on the calendar detail after leaving the batch editor")
        XCTAssertTrue(
            day20Query.firstMatch.label.lowercased().contains("events"),
            "Bug: day 20 is not marked as having events after the edit (label: '\(day20Query.firstMatch.label)')"
        )

        // 8b) Tap the day again. The day now has a batch, so this opens the
        //     day's batch list (the editor dismissed back to the calendar).
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
            "Bug: saving the event then the batch created \(batchNameMatches.count) batches with the same event instead of one"
        )

        // 9) Reopen the batch. It must still contain its event — the reported
        //    bug opens the batch editor with an EMPTY event list.
        batchNameMatches.firstMatch.tap()
        let eventInBatch = app.collectionViews.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "Edited Event"))
            .firstMatch
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

        // The event now carries the batch color.
        let reopenedEventRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Event1")).firstMatch
        XCTAssertTrue(reopenedEventRow.waitForExistence(timeout: 5))
        reopenedEventRow.tap()

        XCTAssertTrue(app.textFields["event-name-field"].waitForExistence(timeout: 5))
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

        let reopenedEventRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Event1")).firstMatch
        XCTAssertTrue(reopenedEventRow.waitForExistence(timeout: 5))
        reopenedEventRow.tap()

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
