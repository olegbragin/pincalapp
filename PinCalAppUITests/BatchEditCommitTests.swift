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

    /// STR regression: edit a batch (add an event), press Save, go back to the
    /// calendar. The newly selected day must immediately behave as a day with
    /// events (opens the batch list, not a new-batch editor).
    @MainActor
    func testSavingBatchFromEditorUpdatesCalendarWithoutReachingRoot() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Day with an existing batch -> batch list -> batch editor.
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)

        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should show the seeded batch")
        batchRow.tap()

        // Select an additional event on an empty day inside the editor.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        // Save via the toolbar checkmark.
        let saveButton = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button should be visible in the editor")
        saveButton.tap()

        // Editor dismissed back to the batch list; go back to the calendar.
        XCTAssertFalse(
            saveButton.waitForExistence(timeout: 2),
            "Editor should be dismissed after Save"
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
    func testEditingExistingEventShowsPreFilledNameAndPersistsChanges() throws {
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

        // Append text and save.
        nameField.tap()
        nameField.typeText("Renamed")
        let eventSaveButton = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 3), "Event save button should be visible")
        eventSaveButton.tap()

        // Back in the batch editor, save the batch.
        let batchSaveButton = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5), "Batch save button should be visible after event save")
        batchSaveButton.tap()

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
        XCTAssertEqual(persistedName, "Event1Renamed", "Event name must persist after save and reopen")
    }

    /// STR regression for the reported bug:
    /// 1) Open calendar -> tap day with batch -> batch list
    /// 2) Tap batch -> batch editor
    /// 3) Tap event -> event editor
    /// 4) Change name, Save (event)
    /// 5) Save (batch) -> back to batch list
    /// 6) Tap same batch again
    /// AB was old name; EB is renamed name persists without ever returning to the calendar root.
    @MainActor
    func testRenamedEventPersistsWhenReopeningBatchImmediately() throws {
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
        let eventSaveButton = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 3))
        eventSaveButton.tap()

        // Batch editor Save -> back to batch list
        let batchSaveButton = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5), "Batch Save should be visible after event Save")
        batchSaveButton.tap()
        XCTAssertFalse(
            batchSaveButton.waitForExistence(timeout: 2),
            "Batch editor should be dismissed after Save"
        )

        // Should be back at batch list, without navigating to calendar
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Should be back at batch list after batch Save")

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
    /// 6) Save (event)   -> auto-persists the batch
    /// 7) Save (batch)
    /// 8) Tap the day again
    /// EB: exactly one batch in the list. AB: two batches with the same event.
    @MainActor
    func testSavingEventThenSavingNewBatchDoesNotDuplicateIt() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // 2) Tap an empty day -> new-batch editor with a placeholder event.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        // 3) Enter the batch name.
        let batchNameField = app.textFields["batch-name-field"]
        XCTAssertTrue(batchNameField.waitForExistence(timeout: 5), "Batch editor should open for the tapped day")
        KeyboardAvoidanceTestSupport.replaceText(in: batchNameField, with: "Edited Batch")

        // 3b) Give the batch a colour. `PCEventBatchAssembleUnitOfWork.canSave` requires a name, a
        //     colour and at least one day, and the event editor's own Save is
        //     disabled until the event has one too — a day tapped on the calendar
        //     starts the batch with `colorName: ""`. Without this step both Saves
        //     are disabled, tapping them is a no-op, and the batch editor never
        //     comes back. Recolouring the batch propagates to its events, so the
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

        // 6) Save the event (auto-persists the batch, store assigns a real id).
        let eventSaveButton = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 5), "Event save button should be visible")
        eventSaveButton.tap()

        // 7) Save the batch.
        let batchSaveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5), "Back in the batch editor after the event save")
        batchSaveButton.tap()
        XCTAssertFalse(
            batchSaveButton.waitForExistence(timeout: 2),
            "Batch editor should be dismissed after Save"
        )

        // 8a) The editor dismissed back to the calendar detail. The day we just
        //     saved must now be MARKED as having events. The reported bug leaves
        //     it unmarked because the saved batch holds no events.
        let day20ID = KeyboardAvoidanceTestSupport.dayIdentifier(day: 20)
        let day20Query = app.descendants(matching: .any).matching(identifier: day20ID)
        XCTAssertTrue(day20Query.firstMatch.waitForExistence(timeout: 5), "Should be back on the calendar detail after the batch Save")
        XCTAssertTrue(
            day20Query.firstMatch.label.lowercased().contains("events"),
            "Bug: day 20 is not marked as having events after the Save (label: '\(day20Query.firstMatch.label)')"
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
        while Date() < settleDeadline { Thread.sleep(forTimeInterval: 0.2) }

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
    /// in the batch) must persist after batch Save and calendar round-trip.
    @MainActor
    func testChangingEventColorPersistsAfterBatchSave() throws {
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

        let batchSaveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5))
        batchSaveButton.tap()

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
    func testChangingEventColorPersistsWhenReopeningBatchImmediately() throws {
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

        let batchSaveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5))
        batchSaveButton.tap()
        XCTAssertFalse(batchSaveButton.waitForExistence(timeout: 2), "Batch editor should be dismissed after Save")
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
    func testDeletingEventFromBatchListUnmarksCalendar() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")

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
               !day1Query.firstMatch.label.lowercased().contains("events") {
                day1Marked = false
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(day1Marked,
                       "Day 1 should be unmarked after its event was deleted")
    }
}
