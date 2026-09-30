//
//  EmptyDayTapMarkerTests.swift
//  PinCalAppUITests
//
//  STR: open a calendar, tap a day that has no events on it.
//
//  AB: the batch editor opens with the tapped day **unmarked** in its calendar. Pressing
//      back then leaves a marker on that day, so the day looks like it holds an event that
//      was never saved — marked in memory, absent from the store.
//
//  EB: the tapped day is marked in the batch editor's calendar, and pressing back takes the
//      marker away with the discarded edit.
//
//  Two independent faults, and they are not the same bug. The editor showing nothing is a
//  projection that was never recomputed when the assembly was staged; the marker surviving
//  back is the same projection not being recomputed when the assembly is thrown away. A fix
//  for only the first would leave a phantom marker on every abandoned edit, which is the
//  more misleading of the two — it asserts to the user that something was saved.
//

import XCTest

final class EmptyDayTapMarkerTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openSeededCalendar() -> XCUIApplication {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        return app
    }

    /// The first day in `candidates` that is genuinely empty.
    ///
    /// Picked by observation rather than hard-coded. The seeded calendar's events move
    /// whenever seed data changes, and a test that hard-codes a day and then asserts the day
    /// is empty fails on the fixture, not on the behaviour.
    @MainActor
    private func firstEmptyDay(in app: XCUIApplication, from candidates: [Int]) throws -> Int {
        for day in candidates {
            let cell = KeyboardAvoidanceTestSupport.dayCell(day: day, in: app)
            guard cell.waitForExistence(timeout: 2) else { continue }
            if !cell.label.lowercased().contains("event") { return day }
        }
        XCTFail("None of the candidate days \(candidates) was empty; the seed data changed")
        throw XCTSkip("no empty day available")
    }

    /// A tapped empty day is marked while the editor is open, and unmarked once the edit is
    /// abandoned.
    @MainActor
    func testTappingEmptyDayMarksItInBatchEditorAndBackClearsTheMarker() throws {
        let app = openSeededCalendar()
        let day = try firstEmptyDay(in: app, from: [20, 21, 22, 23, 24])

        let before = KeyboardAvoidanceTestSupport.dayCell(day: day, in: app)
        XCTAssertFalse(
            before.label.lowercased().contains("event"),
            "Day \(day) must start empty or this test proves nothing; label = \(before.label)"
        )

        KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)

        // The editor is what the report is about, so assert we actually got there.
        XCTAssertTrue(
            app.buttons["batch-save-button"].waitForExistence(timeout: 5),
            "Tapping an empty day should open the batch editor"
        )

        // The point of the report. The editor stages an event on the tapped day, and the
        // editor's own calendar is where the user sees that.
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
            """
            The tapped day should be marked in the batch editor's calendar — an event is \
            staged on it. Day \(day) is unmarked; label = \
            \(KeyboardAvoidanceTestSupport.dayCell(day: day, in: app).label)
            """
        )

        // Backing out discards the staged edit, so the marker has to go with it. If it
        // survives, the calendar is telling the user a day holds an event that was never
        // written.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)

        // Wait for the editor to actually leave before reading the day. `dayCell` returns the
        // *topmost hittable* cell, and during the pop transition the editor's calendar is
        // still hittable and still marked — so asserting immediately reads the screen being
        // dismissed and reports a failure that is really a race. Same reason the
        // editor-present assertion above waits for `batch-save-button` first.
        XCTAssertTrue(
            app.buttons["batch-save-button"].waitForNonExistence(timeout: 5),
            "The batch editor should be dismissed after going back"
        )

        XCTAssertFalse(
            KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
            """
            Backing out of the batch editor discards the staged event, so day \(day) must \
            not still be marked; label = \
            \(KeyboardAvoidanceTestSupport.dayCell(day: day, in: app).label)
            """
        )
    }
}
