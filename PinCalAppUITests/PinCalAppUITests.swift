//
//  PinCalAppUITests.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 04.05.2026.
//

import XCTest

final class PinCalAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        Task { @MainActor in
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testEditingBatchRemovesToggledOffEventsFromCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData"]
        app.launch()

        // Open the seeded calendar from the sidebar.
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        let day10 = dayIdentifier(day: 10)
        let day12 = dayIdentifier(day: 12)

        // Tap a day with events: the batch list sheet appears.
        app.descendants(matching: .any).matching(identifier: day10).firstMatch.tap()
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show the existing batch")

        // Open the batch editor.
        womenCycle.tap()
        let editorSave = app.buttons["Save"]
        XCTAssertTrue(editorSave.waitForExistence(timeout: 5), "Batch editor should open")

        // Toggle off both event days inside the editor calendar.
        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        editorCalendar.descendants(matching: .any).matching(identifier: day10).firstMatch.tap()
        editorCalendar.descendants(matching: .any).matching(identifier: day12).firstMatch.tap()

        // Save the edited batch.
        editorSave.tap()
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 2), "Batch list sheet should not reopen while saving")

        // Back on the single calendar, tapping the day must NOT show the batch list again.
        app.descendants(matching: .any).matching(identifier: day10).firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Tapping an empty day should open the batch editor directly")
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 2), "Removed events must not reopen the batch list")
    }

    private func dayIdentifier(day: Int) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = DateComponents(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            day: day
        )
        let date = calendar.date(from: components)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "day-\(formatter.string(from: date))"
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
