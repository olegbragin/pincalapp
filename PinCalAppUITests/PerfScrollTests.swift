//
//  PerfScrollTests.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 13.08.2026.
//

import XCTest

final class PerfScrollTests: XCTestCase {

    @MainActor
    func testScrollYearCalendarAndBatchEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData"]
        app.launch()

        if app.buttons["sidebar-calendars"].waitForExistence(timeout: 2) {
            app.buttons["sidebar-calendars"].tap()
        }
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        // Interact with the batch editor first while the current month is guaranteed on screen.
        let day10 = app.descendants(matching: .any).matching(identifier: dayIdentifier(day: 10)).firstMatch
        XCTAssertTrue(day10.waitForExistence(timeout: 5))
        day10.tap()

        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show the existing batch")
        womenCycle.tap()

        let editorSave = app.buttons["Save"]
        XCTAssertTrue(editorSave.waitForExistence(timeout: 5), "Batch editor should open")

        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        XCTAssertTrue(editorCalendar.waitForExistence(timeout: 5))

        let editorDeadline = Date().addingTimeInterval(20)
        while Date() < editorDeadline {
            editorCalendar.swipeUp(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            editorCalendar.swipeDown(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }

        editorCalendar.descendants(matching: .any).matching(identifier: dayIdentifier(day: 12)).firstMatch.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        editorCalendar.descendants(matching: .any).matching(identifier: dayIdentifier(day: 10)).firstMatch.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        editorSave.tap()

        // Back on the single calendar, drive the year scroll.
        let yearScrollDeadline = Date().addingTimeInterval(40)
        while Date() < yearScrollDeadline {
            app.swipeUp(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            app.swipeDown(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
    }

    private func dayIdentifier(day: Int) -> String {
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
}
