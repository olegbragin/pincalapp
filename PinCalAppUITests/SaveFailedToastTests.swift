//
//  SaveFailedToastTests.swift
//  PinCalAppUITests
//
//  STR: launch with `-UITestFailSaves`, so every calendar write throws, and edit a batch.
//
//  AB: the user is never told. The edit looks saved — the store holds it, the calendar
//      updates — but the row is not in the database, and switching calendars tears down the
//      store that holds the only copy. The work is gone, and nothing said so.
//
//  EB: a toast appears saying the changes could not be saved, with a Retry button, and the
//      calendar switch is refused while the failure stands.
//
//  The failure is worth testing rather than asserting in a unit test, because both halves are
//  user-visible: the toast is a view, and "cannot switch away" is a property of the navigation
//  guard, not of the store. Unit tests cover the store's half — that `failedSave` is recorded
//  and that Retry replays the failed payload.
//

import XCTest

final class SaveFailedToastTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFailing() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSeedData",
            "-UITestColumns", "1",
            "-UITestNameAutosaveSeconds", "0",
            "-UITestFailSaves",
        ]
        return app
    }

    /// The first day that is empty in the seeded calendar.
    @MainActor
    private func firstEmptyDay(in app: XCUIApplication, from candidates: [Int]) throws -> Int {
        for day in candidates {
            let cell = KeyboardAvoidanceTestSupport.dayCell(day: day, in: app)
            guard cell.waitForExistence(timeout: 2) else { continue }
            if !cell.label.lowercased().contains("event") {
                return day
            }
        }
        XCTFail("None of the candidate days \(candidates) was empty; the seed data changed")
        throw XCTSkip("no empty day available")
    }

    /// A failed save must be visible, and must offer a way out.
    @MainActor
    func testAFailedSaveShowsAToastWithRetry() throws {
        let app = launchFailing()
        app.launch()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Editing is what triggers the write. The tap on an empty day alone already writes,
        // so there may be a failure on screen before the editor even opens.
        let day = try firstEmptyDay(in: app, from: [20, 21, 22, 23, 24])
        KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 10),
            "the batch editor should open"
        )

        // The toast is anchored to the calendar, which the editor is pushed on top of. So the
        // editor is closed before looking for it — the failure is recorded either way, but a
        // toast behind a pushed screen is not a toast the user can read.
        //
        // This is worth knowing: had the toast been on the editor instead, the user would
        // have met the failure at the moment they caused it, and this test would not have
        // needed the workaround.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForNonExistence(timeout: 5),
            "the editor should be closed so the calendar's toast is reachable"
        )

        let retry = app.buttons["save-failed-toast-button"]
        XCTAssertTrue(
            retry.waitForExistence(timeout: 10),
            """
            A save that did not land must be visible, with a way to retry. Without this the \
            store is ahead of the database and switching calendars destroys the only copy.
            """
        )
    }
}
