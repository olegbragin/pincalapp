//
//  KeyboardAvoidanceTests.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 24.08.2026.
//

import XCTest

final class KeyboardAvoidanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEditedFieldStaysAboveKeyboardInPortrait() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)

        let (keyboard, nameField, confirmButton) = KeyboardAvoidanceTestSupport.startEditing(cardID: 3, in: app)

        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: nameField, keyboard: keyboard)
        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: confirmButton, keyboard: keyboard)
    }

    @MainActor
    func testGridModeKeepsEditedFieldAboveKeyboard() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)

        let gridToggle = app.buttons["Grid"]
        XCTAssertTrue(gridToggle.waitForExistence(timeout: 5), "Display mode toggle button should exist")
        gridToggle.tap()

        let (keyboard, nameField, confirmButton) = KeyboardAvoidanceTestSupport.startEditing(cardID: 3, in: app)

        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: nameField, keyboard: keyboard)
        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: confirmButton, keyboard: keyboard)
    }

    @MainActor
    func testReturnKeyCommitsRenameWhileKeyboardVisible() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)

        let (_, nameField, _) = KeyboardAvoidanceTestSupport.startEditing(cardID: 3, in: app)

        let currentValue = (nameField.value as? String) ?? ""
        if !currentValue.isEmpty {
            nameField.typeText(String(repeating: "\u{8}", count: currentValue.count))
        }
        nameField.typeText("Renamed by Return\n")

        let renamed = app.staticTexts["Renamed by Return"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), "Return key should commit the rename")
    }
}
