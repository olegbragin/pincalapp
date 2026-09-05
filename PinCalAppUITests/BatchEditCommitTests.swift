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
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)

        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should show the seeded batch")
        batchRow.tap()

        // Select an additional event on an empty day inside the editor.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        // Save via the toolbar checkmark.
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button should be visible in the editor")
        saveButton.tap()

        // Editor dismissed back to the batch list; go back to the calendar.
        XCTAssertFalse(
            saveButton.waitForExistence(timeout: 2),
            "Editor should be dismissed after Save"
        )
        KeyboardAvoidanceTestSupport.tapBackButton(in: app)

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

        // Day 10 has an existing batch with "Event1".
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)

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
        let eventSaveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 3), "Event save button should be visible")
        eventSaveButton.tap()

        // Back in the batch editor, save the batch.
        let batchSaveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5), "Batch save button should be visible after event save")
        batchSaveButton.tap()

        // Dismiss back to the calendar.
        KeyboardAvoidanceTestSupport.tapBackButton(in: app)

        // Re-open the same batch: tap day 10 again.
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
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

        // Day 10 -> batch list -> batch editor
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
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
        let eventSaveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 3))
        eventSaveButton.tap()

        // Batch editor Save -> back to batch list
        let batchSaveButton = app.buttons["Save"].firstMatch
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

    // MARK: - Color change regressions (same STR as name, but changing color)

    @MainActor
    private func selectEventColor(_ colorName: String, in app: XCUIApplication) {
        // Both the batch editor (behind) and the event editor expose a
        // `color-picker-compact`. Tap the topmost hittable one — the event
        // editor's — so the sheet that opens belongs to the screen being edited.
        let pickerQuery = app.buttons.matching(identifier: "color-picker-compact")
        XCTAssertTrue(pickerQuery.firstMatch.waitForExistence(timeout: 5), "Color picker should be visible")
        let deadline = Date().addingTimeInterval(5)
        var target: XCUIElement?
        while target == nil, Date() < deadline {
            target = pickerQuery.allElementsBoundByIndex.reversed().first { $0.isHittable }
            if target == nil { Thread.sleep(forTimeInterval: 0.2) }
        }
        (target ?? pickerQuery.firstMatch).tap()
        let option = app.buttons["color-option-\(colorName)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Color option \(colorName) should be visible in sheet")
        option.tap()
        // Sheet dismisses; verify picker value updated
        XCTAssertTrue(pickerQuery.firstMatch.waitForExistence(timeout: 5))
        // Small delay for binding to propagate
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// Changing the batch color (which is applied to, and rewrites, every event
    /// in the batch) must persist after batch Save and calendar round-trip.
    @MainActor
    func testChangingEventColorPersistsAfterBatchSave() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
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

        KeyboardAvoidanceTestSupport.tapBackButton(in: app)

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
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

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
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

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")

        // The batch editor's calendar marks days that have events.
        let day10 = KeyboardAvoidanceTestSupport.dayIdentifier(day: 10)
        let day12 = KeyboardAvoidanceTestSupport.dayIdentifier(day: 12)
        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        let day10Cell = editorCalendar.descendants(matching: .any).matching(identifier: day10).firstMatch
        let day12Cell = editorCalendar.descendants(matching: .any).matching(identifier: day12).firstMatch
        XCTAssertTrue(day10Cell.waitForExistence(timeout: 5))
        XCTAssertTrue(day12Cell.waitForExistence(timeout: 5))
        XCTAssertTrue(day10Cell.label.lowercased().contains("events"), "Day 10 should be marked")
        XCTAssertTrue(day12Cell.label.lowercased().contains("events"), "Day 12 should be marked")

        // Delete the first event row (on day 10, first in the sorted list).
        let removeControl = app.images.matching(identifier: "minus.circle.fill").firstMatch
        XCTAssertTrue(removeControl.waitForExistence(timeout: 5), "Edit-mode delete control should exist")
        removeControl.tap()
        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button should appear")
        deleteButton.tap()

        // Day 10 must now be unmarked in the top calendar.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && day10Cell.label.lowercased().contains("events") {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(day10Cell.label.lowercased().contains("events"),
                       "Day 10 should be unmarked after its event was deleted; label = \(day10Cell.label)")
    }
}
