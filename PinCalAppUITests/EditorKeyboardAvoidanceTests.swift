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
    func testBatchEditorNameFieldStaysAboveKeyboard() {
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

    // `testEventEditorNameFieldStaysAboveKeyboard` was deleted with the screen. It reached an
    // event's name field by tapping a row in the batch editor's list, and a row is a card now.
    // Nothing is left for it to cover: `batch-name-field` is the only text field in either
    // editor, and `testBatchEditorNameFieldStaysAboveKeyboard` already raises a keyboard
    // against it.
}
