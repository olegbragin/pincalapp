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
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
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
        // Wait for the editor to fully dismiss before checking the day is empty.
        _ = !editorSave.waitForExistence(timeout: 3)

        // Removing every event empties the batch, so the app returns straight to
        // the single calendar view (no empty batch list, no extra Back needed).
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 3), "Removed events must not reopen the batch list")

        // Back on the single calendar, tapping the day must NOT show the batch list again.
        let day10Again = app.descendants(matching: .any).matching(identifier: day10).firstMatch
        XCTAssertTrue(day10Again.waitForExistence(timeout: 5), "Calendar day should be visible after navigating back")
        day10Again.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Tapping an empty day should open the batch editor directly")
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 2), "Removed events must not reopen the batch list")
    }

    @MainActor
    private func openCalendarsList(_ app: XCUIApplication) {
        if app.buttons["sidebar-calendars"].waitForExistence(timeout: 2) {
            app.buttons["sidebar-calendars"].tap()
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

    @MainActor
    func testNavigationToCalendarAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
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
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
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
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
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

    // MARK: - Batch list keeps a batch after its anchor day's event is removed

    @MainActor
    func testBatchListStillShowsBatchAfterRemovingAnchorDay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        // The seeded calendar has "Women Cycle" on days 10 and 12, so we anchor
        // a fresh batch on an empty day (11) and add events on 12 and 13.
        let anchorDay = dayIdentifier(day: 11)
        let addDay1 = dayIdentifier(day: 12)
        let addDay2 = dayIdentifier(day: 13)
        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        let saveButton = app.buttons["batch-save-button"]

        // Tap the empty day and create a batch anchored there with two more days.
        app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open for an empty day")
        nameField.tap()
        nameField.typeText("Cycle")

        editorCalendar.descendants(matching: .any).matching(identifier: addDay1).firstMatch.tap()
        editorCalendar.descendants(matching: .any).matching(identifier: addDay2).firstMatch.tap()
        saveButton.tap()
        XCTAssertTrue(editorCalendar.waitForNonExistence(timeout: 5), "Batch editor should dismiss after Save")

        // Re-open the anchor day: the batch list must contain the batch.
        app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        let cycle = app.staticTexts["Cycle"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 5), "Batch list should contain the batch")

        // Open the batch, remove the anchor day's event, save.
        cycle.tap()
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open for the existing batch")
        editorCalendar.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        saveButton.tap()
        XCTAssertTrue(editorCalendar.waitForNonExistence(timeout: 5), "Batch editor should dismiss after Save")

        // Bug: the batch list must still contain the batch (events remain on 12 & 13).
        XCTAssertTrue(cycle.waitForExistence(timeout: 5),
                      "Batch list should still contain the batch after removing the anchor day")
    }

    // MARK: - Removing the anchor day must uncolor it on the single calendar view

    @MainActor
    func testRemovingAnchorDayUncolorsItOnCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        let anchorDay = dayIdentifier(day: 11)
        let addDay1 = dayIdentifier(day: 12)
        let addDay2 = dayIdentifier(day: 13)
        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        let saveButton = app.buttons["batch-save-button"]

        // Create a batch anchored at day 11 with events on 12 & 13.
        app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open for an empty day")
        nameField.tap()
        nameField.typeText("Cycle")
        editorCalendar.descendants(matching: .any).matching(identifier: addDay1).firstMatch.tap()
        editorCalendar.descendants(matching: .any).matching(identifier: addDay2).firstMatch.tap()
        saveButton.tap()
        XCTAssertTrue(editorCalendar.waitForNonExistence(timeout: 5), "Batch editor should dismiss after Save")

        // The anchor day is marked right after creation (it has an event).
        let dayEl = app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch
        XCTAssertTrue(dayEl.waitForExistence(timeout: 5), "Anchor day should be visible on the calendar")
        XCTAssertTrue(dayEl.label.lowercased().contains("event"),
                      "Anchor day should be marked after creation; label = \(dayEl.label)")

        // Open the batch, remove the anchor day's event, save.
        app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        let cycle = app.staticTexts["Cycle"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 5), "Batch list should contain the batch")
        cycle.tap()
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")
        editorCalendar.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        saveButton.tap()
        XCTAssertTrue(editorCalendar.waitForNonExistence(timeout: 5), "Batch editor should dismiss after Save")

        // Pop back to the single calendar view.
        let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "Batch list back button should exist")
        back.tap()

        // The anchor day must no longer be marked (its event was removed).
        let dayAfter = app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Anchor day should still be visible")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Anchor day must NOT be marked after removing its event; label = \(dayAfter.label)")

        // Days that still have events must remain marked.
        let day12 = app.descendants(matching: .any).matching(identifier: addDay1).firstMatch
        XCTAssertTrue(day12.waitForExistence(timeout: 5))
        XCTAssertTrue(day12.label.lowercased().contains("event"),
                      "Day 12 should remain marked; label = \(day12.label)")
    }

    // MARK: - Removing all batches returns to the single calendar view

    @MainActor
    func testRemovingAllBatchesReturnsToSingleCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        let anchorDay = dayIdentifier(day: 11)
        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        let saveButton = app.buttons["batch-save-button"]

        // Create a batch on an empty day.
        app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open")
        nameField.tap()
        nameField.typeText("Cycle")
        saveButton.tap()
        XCTAssertTrue(editorCalendar.waitForNonExistence(timeout: 5), "Batch editor should dismiss")

        // Open the day's batch list and delete the only batch.
        app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch.tap()
        let batch = app.staticTexts["Cycle"]
        XCTAssertTrue(batch.waitForExistence(timeout: 5), "Batch list should contain the batch")

        let removeControl = app.images.matching(identifier: "minus.circle.fill").firstMatch
        XCTAssertTrue(removeControl.waitForExistence(timeout: 5), "Edit-mode delete control should exist")
        removeControl.tap()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button should appear")
        deleteButton.tap()

        // Back on the single calendar view, the batch is deleted and the day is unmarked.
        let dayAfter = app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Should be back on the single calendar view")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Batch should be deleted and the day unmarked; label = \(dayAfter.label)")
        XCTAssertFalse(app.staticTexts["Cycle"].waitForExistence(timeout: 2), "Batch list should be gone")
    }

    // MARK: - Removing all events deletes the batch and returns to the single calendar view

    @MainActor
    func testRemovingAllEventsFromBatchDeletesItAndReturnsToCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        let day10 = dayIdentifier(day: 10)
        let day12 = dayIdentifier(day: 12)
        let editorCalendar = app.descendants(matching: .any).matching(identifier: "batch-editor-calendar").firstMatch
        let saveButton = app.buttons["batch-save-button"]

        // Open the seeded "Women Cycle" batch (day 10 -> batch list -> batch).
        app.descendants(matching: .any).matching(identifier: day10).firstMatch.tap()
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show Women Cycle")
        womenCycle.tap()
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")

        // Remove both events (days 10 & 12) so the batch becomes empty.
        editorCalendar.descendants(matching: .any).matching(identifier: day10).firstMatch.tap()
        editorCalendar.descendants(matching: .any).matching(identifier: day12).firstMatch.tap()
        saveButton.tap()

        // Back on the single calendar view: the batch is deleted and day 10 unmarked.
        let dayAfter = app.descendants(matching: .any).matching(identifier: day10).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Should be back on the single calendar view")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Batch should be deleted and day 10 unmarked; label = \(dayAfter.label)")
    }

    // MARK: - Deleting events from the batch editor's events list

    @MainActor
    func testDeletingAllEventsFromBatchEditorListDeletesBatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        let day10 = dayIdentifier(day: 10)
        let saveButton = app.buttons["batch-save-button"]

        // Open the seeded "Women Cycle" batch (day 10 -> batch list -> batch).
        app.descendants(matching: .any).matching(identifier: day10).firstMatch.tap()
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show Women Cycle")
        womenCycle.tap()
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")

        // The seeded batch has two events, so its events list exposes two
        // edit-mode delete controls. Delete them all.
        let removeControl = app.images.matching(identifier: "minus.circle.fill")
        for _ in 0..<2 {
            XCTAssertTrue(removeControl.firstMatch.waitForExistence(timeout: 5), "Event delete control should exist")
            removeControl.firstMatch.tap()
            let deleteButton = app.buttons["Delete"].firstMatch
            XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button should appear")
            deleteButton.tap()
        }

        // Removing every event empties the batch; Save deletes it and returns
        // to the single calendar view with day 10 unmarked.
        saveButton.tap()

        let dayAfter = app.descendants(matching: .any).matching(identifier: day10).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Should be back on the single calendar view")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Batch deleted via the events list should leave day 10 unmarked; label = \(dayAfter.label)")
    }
}
