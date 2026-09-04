//
//  KeyboardAvoidanceTestSupport.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 24.08.2026.
//

import XCTest

enum KeyboardAvoidanceTestSupport {

    @MainActor
    static func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()
        return app
    }

    @MainActor
    static func openCalendarsList(_ app: XCUIApplication) {
        if app.buttons["sidebar-calendars"].waitForExistence(timeout: 2) {
            app.buttons["sidebar-calendars"].tap()
        }
    }

    @MainActor
    static func openCalendarDetail(_ app: XCUIApplication, named name: String) {
        openCalendarsList(app)
        let calendarRow = app.staticTexts[name].firstMatch
        XCTAssertTrue(calendarRow.waitForExistence(timeout: 5), "Calendar '\(name)' should exist in the list")
        calendarRow.tap()
    }

    @MainActor
    static func tapDay(day: Int, in app: XCUIApplication) {
        let identifier = dayIdentifier(day: day)
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 5), "Day cell \(identifier) should exist")

        // Several screens can expose the same day id (main calendar under a
        // pushed editor); tap the topmost hittable one.
        let deadline = Date().addingTimeInterval(5)
        var target: XCUIElement?
        while Date() < deadline, target == nil {
            target = query.allElementsBoundByIndex.reversed().first { $0.isHittable }
            if target == nil {
                Thread.sleep(forTimeInterval: 0.2)
                _ = query.firstMatch.exists
            }
        }
        let cell = target ?? query.firstMatch

        // The year grid reflows (and animates) when its column count clamps on
        // appear/size change, so a cell's reported frame can be stale at tap
        // time. A tap at a stale center then lands on an adjacent day (often
        // the same cell of the neighbouring month), which is the source of
        // flaky day taps on the iPad split view. Wait until the frame stops
        // moving before tapping.
        _ = stableFrame(of: cell, timeout: 4)

        cell.tap()
    }

    static func dayIdentifier(day: Int) -> String {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let components = DateComponents(year: year, month: month, day: day)
        let date = calendar.date(from: components)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let gridMonth = String(format: "%02d", month)
        return "day-\(gridMonth)-\(formatter.string(from: date))"
    }

    @MainActor
    static func tapBackButton(in app: XCUIApplication) {
        // iPad split-view exposes several navigation bars at once, so
        // `navigationBars.firstMatch` resolves to the wrong bar (often the
        // sidebar's "Hide Sidebar"). Prefer the explicit SwiftUI back button.
        let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button should be visible")
        back.tap()
    }

    @MainActor
    static func scrollElementIntoView(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while swipes < maxSwipes {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    @MainActor
    static func startEditing(cardID: Int64, in app: XCUIApplication) -> (keyboard: XCUIElement, nameField: XCUIElement, confirmButton: XCUIElement) {
        let editButton = app.buttons["card-edit-\(cardID)"]
        scrollElementIntoView(editButton, in: app)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit button of calendar \(cardID) should exist")
        if !editButton.isHittable {
            app.swipeDown()
        }
        editButton.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Keyboard should appear when editing starts")

        let nameField = app.textFields["card-name-field-\(cardID)"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Name field should appear in editing mode")
        let confirmButton = app.buttons["card-confirm-edit-\(cardID)"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3), "Confirm button should appear in editing mode")

        return (keyboard, nameField, confirmButton)
    }

    @MainActor
    static func assertAboveKeyboard(
        element: XCUIElement,
        keyboard: XCUIElement,
        tolerance: CGFloat = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let elementFrame = stableFrame(of: element)
        let keyboardFrame = stableFrame(of: keyboard)

        // In landscape mode the keyboard can be floating (minY ≈ 0).
        // When that happens the positional check is not meaningful —
        // just verify the element is still on screen and interactable.
        let keyboardAnchored = keyboardFrame.minY > 40
        if keyboardAnchored {
            XCTAssertLessThanOrEqual(
                elementFrame.maxY,
                keyboardFrame.minY + tolerance,
                "\(element.elementType.rawValue) bottom (\(elementFrame.maxY)) must stay above keyboard top (\(keyboardFrame.minY))",
                file: file,
                line: line
            )
        } else {
            XCTAssertTrue(
                element.isHittable,
                "\(element.elementType.rawValue) must remain visible and hittable when the keyboard is shown (floating)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    static func stableFrame(of element: XCUIElement, timeout: TimeInterval = 4) -> CGRect {
        var previousFrame = CGRect.null
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            guard element.exists else { break }
            let currentFrame = element.frame
            let valid = currentFrame.width > 1 && currentFrame.height > 1
            let settled = valid
                && abs(currentFrame.minX - previousFrame.minX) < 1
                && abs(currentFrame.minY - previousFrame.minY) < 1
                && abs(currentFrame.width - previousFrame.width) < 1
                && abs(currentFrame.height - previousFrame.height) < 1
            previousFrame = currentFrame
            if settled {
                return currentFrame
            }
        }
        return previousFrame.isNull ? .zero : previousFrame
    }
}
