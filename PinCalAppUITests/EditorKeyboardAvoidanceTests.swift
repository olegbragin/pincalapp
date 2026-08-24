//
//  EditorKeyboardAvoidanceTests.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 24.08.2026.
//

import XCTest

final class EditorKeyboardAvoidanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBatchEditorNameFieldStaysAboveKeyboard() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // An empty day opens the batch editor directly.
        KeyboardAvoidanceTestSupport.tapDay(day: 20, in: app)

        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open when tapping an empty day")
        nameField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Keyboard should appear when the name field is focused")

        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: nameField, keyboard: keyboard)
    }

    @MainActor
    func testEventEditorNameFieldStaysAboveKeyboard() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // A day with events opens the batch list first.
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)

        let batchRow = app.staticTexts["Women Cycle"]
        XCTAssertTrue(batchRow.waitForExistence(timeout: 5), "Batch list should show the seeded batch")
        batchRow.tap()

        // The batch editor opens with the events list; tap an event to edit it.
        let eventRow = app.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "Event1"))
            .firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "Event row should exist in the batch editor")
        eventRow.tap()

        let nameField = app.textFields["event-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Event editor should open after tapping an event")
        nameField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Keyboard should appear when the name field is focused")

        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: nameField, keyboard: keyboard)
    }
}
