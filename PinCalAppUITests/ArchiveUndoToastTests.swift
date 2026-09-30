//
//  ArchiveUndoToastTests.swift
//  PinCalAppUITests
//
//  STR: open the calendar list, archive a calendar, press Undo on the toast.
//
//  AB: the restored calendar does not come back to the active list.
//  EB: it does.
//
//  ## The test affordances this relies on, and why they exist
//
//  - **The toast names itself** (`archive-undo-toast`) and its action is a real `Button`
//    (`archive-undo-toast-button`). The action used to be a `Text` inside a tap gesture on
//    the whole toast, so "press Undo" was not expressible — only "tap the toast somewhere
//    near the right", which passes by luck and fails by geography.
//  - **The undo window is injected** (`-UITestUndoWindowSeconds`). A toast lives ~5 seconds.
//    Asking a test to find one inside that is a coin flip on a loaded simulator, and a flaky
//    test is worse than none, because it looks like coverage. Production still uses 5s.
//

import XCTest

@MainActor
final class ArchiveUndoToastTests: XCTestCase {

    private let calendar = "UI Test Calendar"
    private let toastIdentifier = "archive-undo-toast"
    private let undoIdentifier = "archive-undo-toast-button"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ app: XCUIApplication) {
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1", "-UITestUndoWindowSeconds", "120"]
        app.launch()
    }

    /// The card's own archive button, found by id.
    ///
    /// This used to pick the nearest `"trash"` button to the calendar name's vertical
    /// midpoint — a geometric guess that silently archives *whatever card happened to be
    /// closest*, which is a fine plan right up until the list re-sorts or two cards share a
    /// row. The button carries its calendar's id now, so there is nothing to guess.
    private func archiveButton(for calendarID: Int64, in app: XCUIApplication) -> XCUIElement {
        app.buttons["card-archive-\(calendarID)"]
    }

    private func openList(_ app: XCUIApplication) {
        KeyboardAvoidanceTestSupport.openCalendarsList(app)
        XCTAssertTrue(
            app.staticTexts[calendar].waitForExistence(timeout: 15),
            "The seeded calendar list should load"
        )
    }

    /// Archiving and then undoing puts the calendar back in the active list.
    func testUndoOnTheArchiveToastRestoresTheCalendarToTheActiveList() {
        let app = XCUIApplication()
        launch(app)
        openList(app)

        let countBefore = app.staticTexts.matching(NSPredicate(format: "label == %@", calendar)).count
        XCTAssertEqual(countBefore, 1, "The calendar should start present exactly once")

        // 1. Archive it. The seeded calendar is id 1; see `UITestStoreFactory`.
        let calendarID: Int64 = 1
        XCTAssertTrue(
            app.buttons["card-name-field-\(calendarID)"].exists || app.staticTexts[calendar].exists,
            "The seeded calendar's card should be on screen"
        )
        archiveButton(for: calendarID, in: app).tap()

        // 2. The toast is up, with a real Undo button on it.
        // Queried over `descendants`, not by element type: a SwiftUI container's identifier
        // lands on whatever element type the framework decides to synthesise, and a
        // `.otherElements` subscript that does not match is a query that silently matches
        // nothing — which is exactly how "the toast is missing" and "the toast is the wrong
        // class" become indistinguishable.
        let toast = app.descendants(matching: .any).matching(identifier: toastIdentifier).firstMatch
        let undo = app.descendants(matching: .any).matching(identifier: undoIdentifier).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "Archiving should show the undo toast")
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "The toast should expose an Undo button")

        // 3. Press Undo.
        undo.tap()

        // 4. The point of the report: the calendar is back.
        XCTAssertTrue(
            app.staticTexts[calendar].waitForExistence(timeout: 10),
            """
            Undoing an archive should put '\(calendar)' back in the active list. It did not \
            reappear — the restore is published as a *delete*, so the list folds in a removal \
            for a calendar that was never there.
            """
        )
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", calendar)).count, 1,
            "The restored calendar should appear exactly once, not be duplicated by the undo"
        )
    }
}
