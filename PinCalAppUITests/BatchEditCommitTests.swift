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
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Back button should be visible")
        backButton.tap()

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
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Back button should be visible")
        backButton.tap()

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
        let picker = app.buttons["color-picker-compact"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Color picker should be visible")
        picker.tap()
        let option = app.buttons["color-option-\(colorName)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Color option \(colorName) should be visible in sheet")
        option.tap()
        // Sheet dismisses; verify picker value updated
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // Small delay for binding to propagate
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// Changing event color (not just name) must persist after batch Save and calendar round-trip.
    @MainActor
    func testChangingEventColorPersistsAfterBatchSave() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        let eventRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Event1")).firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5))
        eventRow.tap()

        let nameField = app.textFields["event-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        // Verify initial color is option1 via picker value
        let picker = app.buttons["color-picker-compact"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption1", "Initial event color should be option1")

        // Change to option2
        selectEventColor("eventColorOption2", in: app)

        let eventSaveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 3))
        eventSaveButton.tap()

        let batchSaveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(batchSaveButton.waitForExistence(timeout: 5))
        batchSaveButton.tap()

        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        let reopenedEventRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Event1")).firstMatch
        XCTAssertTrue(reopenedEventRow.waitForExistence(timeout: 5))
        reopenedEventRow.tap()

        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption2", "Persisted color must be option2 after save and reopen via calendar")
    }

    /// Changing event color must also persist when reopening batch immediately without returning to calendar root.
    @MainActor
    func testChangingEventColorPersistsWhenReopeningBatchImmediately() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5))
        batchRow.tap()

        let eventRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Event1")).firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5))
        eventRow.tap()

        let picker = app.buttons["color-picker-compact"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String ?? "", "eventColorOption1")

        selectEventColor("eventColorOption3", in: app)

        let eventSaveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(eventSaveButton.waitForExistence(timeout: 3))
        eventSaveButton.tap()

        let batchSaveButton = app.buttons["Save"].firstMatch
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
}
