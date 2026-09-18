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
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Interact with the batch editor first while the current month is guaranteed on screen.
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)

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

        KeyboardAvoidanceTestSupport.tapDay(day: 12, in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        KeyboardAvoidanceTestSupport.tapDay(day: 10, in: app)
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
}