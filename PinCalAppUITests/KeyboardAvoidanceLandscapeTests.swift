//
//  KeyboardAvoidanceLandscapeTests.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 24.08.2026.
//

import XCTest

final class KeyboardAvoidanceLandscapeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        Task { @MainActor in
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testEditedFieldStaysAboveKeyboardInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.0)

        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)

        let (keyboard, nameField, confirmButton) = KeyboardAvoidanceTestSupport.startEditing(cardID: 1, in: app)

        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: nameField, keyboard: keyboard)
        KeyboardAvoidanceTestSupport.assertAboveKeyboard(element: confirmButton, keyboard: keyboard)
    }
}
