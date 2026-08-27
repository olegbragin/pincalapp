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
        let app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testEditingBatchRemovesToggledOffEventsFromCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData"]
        app.launch()

        // Navigate: sidebar → Calendars → calendar
        openCalendarsList(app)
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
        // Wait for the editor sheet to fully dismiss before checking the batch list doesn't reappear.
        _ = !editorSave.waitForExistence(timeout: 3)

        // The editor dismisses back to the batch list. Pop back to the calendar.
        let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
        if back.waitForExistence(timeout: 3) {
            back.tap()
        }

        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 3), "Batch list sheet should not reopen while saving")

        // Back on the single calendar, tapping the day must NOT show the batch list again.
        let day10Again = app.descendants(matching: .any).matching(identifier: day10).firstMatch
        XCTAssertTrue(day10Again.waitForExistence(timeout: 5), "Calendar day should be visible after navigating back")
        day10Again.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Tapping an empty day should open the batch editor directly")
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 2), "Removed events must not reopen the batch list")
    }

    private func openCalendarsList(_ app: XCUIApplication) {
        if app.buttons["sidebar-calendars"].waitForExistence(timeout: 2) {
            app.buttons["sidebar-calendars"].tap()
        }
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
    func testNavigationToCalendarAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData"]
        app.launch()

        // Navigate to the calendar list via sidebar.
        openCalendarsList(app)

        let calendarName = app.staticTexts["UI Test Calendar"]
        XCTAssertTrue(calendarName.waitForExistence(timeout: 5), "Calendar list should show the seeded calendar")

        calendarName.tap()

        let multiselectButton = app.buttons["Multiselect"]
        XCTAssertTrue(multiselectButton.waitForExistence(timeout: 5), "Detail view should appear after tapping a calendar")

        let backButton = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
        guard backButton.waitForExistence(timeout: 3) else {
            return
        }
        backButton.tap()

        // On compact, Back goes to the content column (calendar list).
        XCTAssertTrue(calendarName.waitForExistence(timeout: 5), "Calendar list should be visible after popping")

        calendarName.tap()
        XCTAssertTrue(multiselectButton.waitForExistence(timeout: 5), "Re-selecting the same calendar should work")
    }

    @MainActor
    func testiPadSidebarSelectsDetailCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData"]
        app.launch()

        // Navigate to the calendar list via sidebar (iPad shows sidebar; iPhone skips to content).
        openCalendarsList(app)

        let firstCalendar = app.staticTexts["UI Test Calendar"].firstMatch
        let secondCalendar = app.staticTexts["Second Calendar"].firstMatch
        guard firstCalendar.waitForExistence(timeout: 5),
              secondCalendar.waitForExistence(timeout: 3) else {
            return
        }

        firstCalendar.tap()
        let detail1 = app.otherElements["calendar-detail-1"]
        guard detail1.waitForExistence(timeout: 5) else { return }

        if !secondCalendar.exists {
            let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
            back.tap()
            _ = firstCalendar.waitForExistence(timeout: 3)
        }

        secondCalendar.tap()
        let detail2 = app.otherElements["calendar-detail-2"]
        XCTAssertTrue(detail2.waitForExistence(timeout: 5), "Detail should switch to second calendar (id 2)")
        XCTAssertFalse(detail1.waitForExistence(timeout: 2), "First calendar detail should no longer be visible")

        if !firstCalendar.exists {
            let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
            back.tap()
            _ = secondCalendar.waitForExistence(timeout: 3)
        }

        firstCalendar.tap()
        XCTAssertTrue(detail1.waitForExistence(timeout: 5), "Tapping first calendar again should bring back its detail")
        XCTAssertFalse(detail2.waitForExistence(timeout: 2), "Second calendar detail should no longer be visible")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCalendarNameEditingKeyboardScroll() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData"]
        app.launch()

        // Navigate to the calendar list via sidebar.
        openCalendarsList(app)

        let thirdCalendar = app.staticTexts["Third Calendar"].firstMatch
        guard thirdCalendar.waitForExistence(timeout: 5) else {
            XCTFail("Third Calendar should exist in seeded data")
            return
        }

        // Scroll down to make sure the third card is visible (it may be off-screen).
        app.swipeUp()

        // The third calendar's edit button should be visible.
        let editButton = app.buttons["card-edit-3"]
        guard editButton.waitForExistence(timeout: 5) else {
            XCTFail("Edit button on third calendar should exist")
            return
        }
        if !editButton.isHittable {
            app.swipeUp()
        }
        editButton.tap()

        // The text field should appear and be tappable (not hidden behind keyboard).
        let nameField = app.textFields["card-name-field-3"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Text text field should appear after tapping edit")

        // Select all existing text and replace with a new name.
        // Using triple-tap avoids relying on the delete key which may not be
        // reachable on some keyboard layouts (e.g. iOS 26.5).
        nameField.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        Thread.sleep(forTimeInterval: 0.3)
        nameField.typeText("Renamed")
        XCTAssertTrue(nameField.exists, "Text field must remain visible while typing (keyboard should not cover it)")

        // Confirm the edit — find the confirm button that appeared.
        let confirmButton = app.buttons["card-confirm-edit-3"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3), "Confirm button should appear")
        confirmButton.tap()

        // The renamed calendar should be visible.
        let renamed = app.staticTexts["Renamed"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), "Calendar should show the new name after saving")
    }
}
