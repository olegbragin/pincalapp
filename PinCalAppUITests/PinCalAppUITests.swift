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
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1", "-UITestNameAutosaveSeconds", "0"]
        app.launch()

        // Navigate to the calendar list via sidebar.
        openCalendarsList(app)

        let calendarName = app.staticTexts["UI Test Calendar"]
        XCTAssertTrue(calendarName.waitForExistence(timeout: 5), "Calendar list should show the seeded calendar")

        calendarName.tap()

        let multiselectButton = KeyboardAvoidanceTestSupport.toolbarAction("Multiselect", in: app)
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
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1", "-UITestNameAutosaveSeconds", "0"]
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
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1", "-UITestNameAutosaveSeconds", "0"]
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

    // MARK: - Batch editing regression tests

    /// Opens the batch editor on `anchorDay` (an empty day), names the batch,
    /// optionally toggles `additionalDays`, saves, and waits for the editor to
    /// dismiss back to the single calendar view.
    @MainActor
    private func createBatch(
        named name: String,
        anchorDay: Int,
        additionalDays: [Int] = [],
        in app: XCUIApplication
    ) {
        KeyboardAvoidanceTestSupport.tapDay(day: anchorDay, in: app)
        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open for the anchor day")

        // Select the additional event days while the keyboard is still down so
        // the year calendar is not covered.
        for day in additionalDays {
            KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)
        }

        // Replace, not append: a new batch arrives with "New event" already in the field
        // (§17.3), so `typeText` here would produce "New eventCycle" and every assertion
        // below would be looking for a name that was never typed.
        KeyboardAvoidanceTestSupport.replaceText(in: nameField, with: name)
        // The colour is already the first available one for a new batch, but selecting it
        // explicitly keeps this helper honest about what the tests it serves depend on.
        KeyboardAvoidanceTestSupport.selectColor("eventColorOption1", in: app)
        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.isEnabled, "Batch editor Save should be enabled once named and coloured")
        saveButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 3), "Batch editor should dismiss after Save")
    }

    @MainActor
    func testEditingBatchRemovesToggledOffEventsFromCalendar() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Tap a day with events: the batch list appears.
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show the existing batch")

        // Open the batch editor.
        womenCycle.tap()
        let editorSave = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(editorSave.waitForExistence(timeout: 5), "Batch editor should open")

        // Toggle off both seeded event days inside the editor's year calendar.
        // **1 and 2** — the seed's days (`TestDataSeeder`). This said 1 and 12, which left
        // day 2's event in place, so the batch was never empty, was never deleted, and the
        // day list reopened: "Removed events must not reopen the batch list".
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        KeyboardAvoidanceTestSupport.tapDay(day: 2, in: app)

        // Save the edited batch. It is now empty, so it is deleted and the app
        // returns straight to the single calendar view.
        editorSave.tap()
        XCTAssertTrue(app.buttons["batch-save-button"].waitForNonExistence(timeout: 3),
                      "Batch editor should dismiss after Save")

        // Removed events must not reopen the batch list.
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 2),
                       "Removed events must not reopen the batch list")

        // Back on the single calendar, tapping the day must NOT show the batch list again.
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        XCTAssertTrue(KeyboardAvoidanceTestSupport.waitForToolbarAction("Save", in: app, timeout: 5),
                      "Tapping an empty day should open the batch editor directly")
        XCTAssertFalse(app.staticTexts["Women Cycle"].waitForExistence(timeout: 2),
                       "Removed events must not reopen the batch list")
    }

    @MainActor
    func testBatchListStillShowsBatchAfterRemovingAnchorDay() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Create a batch anchored at day 11 with events on 12 & 13 (the anchor
        // day gets the staged placeholder event automatically).
        createBatch(named: "Cycle", anchorDay: 11, additionalDays: [12, 13], in: app)

        // Re-open the anchor day: the batch list must contain the batch.
        //
        // The tap is needed. `createBatch` starts from an *empty* day, so the editor was
        // pushed from the calendar rather than from a day list, and the save pops straight
        // back to the calendar. §16.5's re-anchoring only moves you when a day list was on
        // the stack to begin with.
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.openDayBatchesList(day: 11, in: app),
            "The day list for day 11 should open; day 11 now holds a batch"
        )
        let cycle = app.staticTexts["Cycle"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 5), "Batch list should contain the batch")

        // Open the batch, remove the anchor day's event, save.
        cycle.tap()
        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open for the existing batch")
        KeyboardAvoidanceTestSupport.tapDay(day: 11, in: app)
        saveButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 3), "Batch editor should dismiss after Save")

        // Bug regression: removing one of a batch's days must not delete the batch.
        //
        // The save re-anchors the session on the day the batch now lives (§16's fix), so
        // the pop lands on **day 12's** list, not day 11's. That is the point: the batch
        // still exists, but it no longer *occurs* on day 11 — `dayBatches` is
        // `batches.filter { $0.occurs(on: day) }` — so before the fix the pop returned to a
        // day list the batch was not on and rendered empty. Same symptom as §16, one batch.
        //
        // This also used to pass without ever running the edit: Save was disabled (the batch
        // had no colour), so all three events survived, the batch still occurred on day 11,
        // and the assertion was satisfied by a batch nobody had modified.
        XCTAssertTrue(cycle.waitForExistence(timeout: 5),
                      "After removing the anchor day, the save returns to the surviving day's list, which must contain the batch")
        XCTAssertEqual(
            app.staticTexts.matching(identifier: "Cycle").count, 1,
            "and that list must hold exactly one batch, not two and not none"
        )
    }

    @MainActor
    func testRemovingAnchorDayUncolorsItOnCalendar() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Days well clear of the seeded ones (1 and 2), so these tests' own
        // additions cannot collide with the fixture.
        let anchorDay = KeyboardAvoidanceTestSupport.dayIdentifier(day: 11)
        let addDay1 = KeyboardAvoidanceTestSupport.dayIdentifier(day: 12)

        // Create a batch anchored at day 11 with events on 12 & 13.
        createBatch(named: "Cycle", anchorDay: 11, additionalDays: [12, 13], in: app)

        // The anchor day is marked right after creation (it has the placeholder event).
        let dayEl = app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch
        XCTAssertTrue(dayEl.waitForExistence(timeout: 5), "Anchor day should be visible on the calendar")
        XCTAssertTrue(dayEl.label.lowercased().contains("event"),
                      "Anchor day should be marked after creation; label = \(dayEl.label)")

        // Open the batch, remove the anchor day's event, save.
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.openDayBatchesList(day: 11, in: app),
            "The day list for day 11 should open; day 11 now holds a batch"
        )
        let cycle = app.staticTexts["Cycle"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 5), "Batch list should contain the batch")
        cycle.tap()
        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")
        KeyboardAvoidanceTestSupport.tapDay(day: 11, in: app)
        saveButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 3), "Batch editor should dismiss after Save")

        // Pop back to the single calendar view.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)

        // The anchor day must no longer be marked (its event was removed).
        let dayAfter = app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Anchor day should still be visible")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Anchor day must NOT be marked after removing its event; label = \(dayAfter.label)")

        // Days that still have events must remain marked.
        let day2 = app.descendants(matching: .any).matching(identifier: addDay1).firstMatch
        XCTAssertTrue(day2.waitForExistence(timeout: 5))
        XCTAssertTrue(day2.label.lowercased().contains("event"),
                      "Day 2 should remain marked; label = \(day2.label)")
    }

    @MainActor
    func testRemovingAllBatchesReturnsToSingleCalendar() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        let anchorDay = KeyboardAvoidanceTestSupport.dayIdentifier(day: 11)

        // Create a batch on an empty day.
        KeyboardAvoidanceTestSupport.tapDay(day: 11, in: app)
        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open")
        KeyboardAvoidanceTestSupport.replaceText(in: nameField, with: "Cycle")
        // Same as `createBatch`: an uncoloured batch has a disabled Save.
        KeyboardAvoidanceTestSupport.selectColor("eventColorOption1", in: app)
        let saveButton = app.buttons["batch-save-button"]
        saveButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 3), "Batch editor should dismiss")

        // Open the day's batch list and delete the only batch via its trash button.
        KeyboardAvoidanceTestSupport.tapDay(day: 11, in: app)
        let batch = app.staticTexts["Cycle"]
        XCTAssertTrue(batch.waitForExistence(timeout: 5), "Batch list should contain the batch")

        let deleteBatch = app.buttons["Delete batch"].firstMatch
        XCTAssertTrue(deleteBatch.waitForExistence(timeout: 5), "Delete button should exist next to the batch")
        deleteBatch.tap()

        // Back on the single calendar view, the batch is deleted and the day is unmarked.
        let dayAfter = app.descendants(matching: .any).matching(identifier: anchorDay).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Should be back on the single calendar view")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Batch should be deleted and the day unmarked; label = \(dayAfter.label)")
        XCTAssertFalse(app.staticTexts["Cycle"].waitForExistence(timeout: 2), "Batch list should be gone")
    }

    @MainActor
    func testRemovingAllEventsFromBatchDeletesItAndReturnsToCalendar() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        let day1 = KeyboardAvoidanceTestSupport.dayIdentifier(day: 1)

        // Open the seeded "Women Cycle" batch (day 1 -> batch list -> batch).
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show Women Cycle")
        womenCycle.tap()
        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")

        // Remove both seeded events (days 1 & 2) so the batch becomes empty.
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        KeyboardAvoidanceTestSupport.tapDay(day: 2, in: app)
        saveButton.tap()

        // Back on the single calendar view: the batch is deleted and day 1 unmarked.
        let dayAfter = app.descendants(matching: .any).matching(identifier: day1).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Should be back on the single calendar view")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Batch should be deleted and day 1 unmarked; label = \(dayAfter.label)")
    }

    @MainActor
    func testDeletingAllEventsFromBatchEditorListDeletesBatch() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        let day1 = KeyboardAvoidanceTestSupport.dayIdentifier(day: 1)

        // Open the seeded "Women Cycle" batch (day 1 -> batch list -> batch).
        KeyboardAvoidanceTestSupport.tapDay(day: 1, in: app)
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show Women Cycle")
        womenCycle.tap()
        let saveButton = app.buttons["batch-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Batch editor should open")

        // The seeded batch has two events, each with a trash delete button.
        // Delete them all (this removes events directly, no confirmation).
        for _ in 0..<2 {
            let deleteEvent = app.buttons["Delete event"].firstMatch
            XCTAssertTrue(deleteEvent.waitForExistence(timeout: 5), "Event delete button should exist")
            deleteEvent.tap()
        }

        // Removing every event empties the batch; Save deletes it and returns
        // to the single calendar view with day 1 unmarked.
        //
        // The editor's Save is enabled because the seeded batch is named and coloured and
        // an *emptied* batch is still savable — that is what makes emptying a batch a way
        // to delete it. This assertion used to be missing, so the test passed even while
        // Save was disabled and the tap did nothing: it only checked the marker, which the
        // marker fix alone had already made correct, and so it could not tell "the batch was
        // deleted" from "the batch is still open behind us and merely unmarked".
        XCTAssertTrue(saveButton.isEnabled, "An emptied, named, coloured batch must still be savable")
        saveButton.tap()
        XCTAssertTrue(saveButton.waitForNonExistence(timeout: 3),
                      "Saving an emptied batch deletes it and dismisses the editor")

        let dayAfter = app.descendants(matching: .any).matching(identifier: day1).firstMatch
        XCTAssertTrue(dayAfter.waitForExistence(timeout: 5), "Should be back on the single calendar view")
        XCTAssertFalse(dayAfter.label.lowercased().contains("event"),
                       "Batch deleted via the events list should leave day 1 unmarked; label = \(dayAfter.label)")
    }

    // MARK: - Leaving the calendar in multiselect mode resets on reopen

    /// STR: open calendar -> switch to multiselect -> tap back -> reopen the
    /// calendar. It must be back in single-select mode (the toolbar button shows
    /// "Multiselect", not "Save").
    @MainActor
    func testLeavingCalendarInMultiselectModeResetsOnReopen() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        let multiselectButton = KeyboardAvoidanceTestSupport.toolbarAction("Multiselect", in: app)
        XCTAssertTrue(multiselectButton.waitForExistence(timeout: 5), "Multiselect button should be visible")
        multiselectButton.tap()

        // Leave the screen via the back button.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)

        // Reopen the calendar.
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Must be in single-select mode: "Multiselect" button, no "Save".
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.waitForToolbarAction("Multiselect", in: app),
            "After reopening, the calendar should be in single-select mode")
        XCTAssertFalse(
            KeyboardAvoidanceTestSupport.toolbarActionExists("Save", in: app),
            "Save button indicates multiselect mode; should be single")
    }

    // MARK: - Stage 11: the multi-day scenario

    /// The multi-select path, end to end, and the one §6.3 row with no end-to-end cover.
    ///
    /// `confirmMultiSelectTapped` has unit coverage but no UI coverage, and it is the only
    /// way a batch gets more than one day at creation time — every other route builds a
    /// batch on one day and toggles the rest in afterwards. The assertion is deliberately
    /// about **one batch with two days**, not two batches: a per-day batch would satisfy
    /// "the days are marked" and still be the wrong model.
    ///
    /// STR: multiselect -> pick a colour -> tap two days -> confirm -> save -> re-open each
    /// day and find the same single batch on both.
    @MainActor
    func testMultiselectTwoDaysProducesOneBatchWithBothDays() throws {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")

        // Enter the session.
        let multiselect = KeyboardAvoidanceTestSupport.toolbarAction("Multiselect", in: app)
        XCTAssertTrue(multiselect.waitForExistence(timeout: 5), "Multiselect button should be visible")
        multiselect.tap()

        // The picker appears only in the session. A colour is required: the reducer
        // declines `confirmMultiSelectTapped` without one, so the toolbar Save would be a
        // no-op and the test would fail later for the wrong reason.
        let colourOption = app.buttons["color-option-eventColorOption3"]
        XCTAssertTrue(colourOption.waitForExistence(timeout: 5),
                      "The expanded colour picker should be visible in a multi-select session")
        colourOption.tap()

        // Two empty days. Both must be clear of the seed, which only uses 10 and 12.
        KeyboardAvoidanceTestSupport.tapDay(day: 17, in: app)
        KeyboardAvoidanceTestSupport.tapDay(day: 18, in: app)

        // Confirm. The toolbar button reads "Save" while a session is live.
        let confirm = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Toolbar should offer Save during a session")
        confirm.tap()

        // Confirming ends the session rather than opening the editor: the days were written as
        // they were tapped, so there is nothing staged left to review or commit.
        XCTAssertFalse(
            app.buttons["batch-save-button"].exists,
            "Confirming a session should not open the batch editor"
        )

        // The batch carries its default name, since no editor ever opened to rename it. Hard
        // coded rather than the constant: this target is not linked against
        // SingleCalendarFeature, so referencing it fails to link.
        let batchName = "New event"

        // Back on the calendar: both days are marked.
        for day in [17, 18] {
            let cell = app.descendants(matching: .any)
                .matching(identifier: KeyboardAvoidanceTestSupport.dayIdentifier(day: day))
                .firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "Day \(day) should be on the calendar")
            XCTAssertTrue(cell.label.lowercased().contains("event"),
                          "Day \(day) should be marked; label = \(cell.label)")
        }

        // The shape assertion. A batch is listed on *every* day it holds an event on, so if
        // each day shows the same single card, the two days are one batch — not two batches
        // of one day each, which would satisfy "both days are marked" and still be wrong.
        KeyboardAvoidanceTestSupport.tapDay(day: 17, in: app)
        let card = app.staticTexts[batchName]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Day 17's list should contain the batch")
        XCTAssertEqual(app.staticTexts.matching(identifier: batchName).count, 1,
                       "Day 17's list must hold exactly one batch, not one per day")
        card.tap()

        // The authoritative check on the shape: one batch, two events.
        let batchSave = app.buttons["batch-save-button"]
        XCTAssertTrue(batchSave.waitForExistence(timeout: 5), "The batch should open for editing")
        let rows = app.collectionViews.buttons.containing(NSPredicate(format: "label CONTAINS %@", "at"))
        XCTAssertEqual(rows.count, 2, "The batch must hold both days, as two event rows")
        batchSave.tap()

        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)
// Leaving dismisses the calendar, so re-open it before tapping a day.
// On the iPhone the calendar stayed selected and this was not needed, which is
// why it went unnoticed; on the iPad the leave returns to the *list* and there is
// no day cell to tap.
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        KeyboardAvoidanceTestSupport.tapDay(day: 18, in: app)
        let sameCard = app.staticTexts[batchName]
        XCTAssertTrue(sameCard.waitForExistence(timeout: 5),
                      "Day 18 must list the same single batch, not a second one")
        XCTAssertEqual(app.staticTexts.matching(identifier: batchName).count, 1,
                       "Day 18's list must also hold exactly one batch")
    }

    @MainActor
    func testEditingEventInBatchPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestNameAutosaveSeconds", "0"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        // Tap an empty day to create a new event batch.
        let day5 = dayIdentifier(day: 5)
        let day5Element = app.descendants(matching: .any).matching(identifier: day5).firstMatch
        XCTAssertTrue(day5Element.waitForExistence(timeout: 5), "Calendar should load")
        day5Element.tap()

        // Batch editor opens for a new day. Enter a batch name and save.
        let batchNameField = app.textFields["batch-name-field"]
        XCTAssertTrue(batchNameField.waitForExistence(timeout: 5), "Batch editor should open")
        KeyboardAvoidanceTestSupport.replaceText(in: batchNameField, with: "Swim")
        // The batch needs a colour before its Save is enabled, and the event editor's own
        // Save needs the event to have one too — recolouring the batch propagates to its
        // events, so picking it here covers both.
        KeyboardAvoidanceTestSupport.selectColor("eventColorOption1", in: app)
        app.buttons["batch-save-button"].tap()

        // Back on the calendar. Tap the day again to open the batch list, then the batch.
        let day5Again = app.descendants(matching: .any).matching(identifier: day5).firstMatch
        XCTAssertTrue(day5Again.waitForExistence(timeout: 5), "Day should be visible after saving")
        day5Again.tap()
        let swimBatch = app.staticTexts["Swim"]
        XCTAssertTrue(swimBatch.waitForExistence(timeout: 5), "Batch list should show the new batch")
        swimBatch.tap()

        // Batch editor opens. Tap the event to open the event editor.
        let eventCell = app.cells.firstMatch
        XCTAssertTrue(eventCell.waitForExistence(timeout: 5), "Batch editor should list the event")
        eventCell.tap()

        // Event editor opens. Enter the event name and save.
        let eventNameField = app.textFields["event-name-field"]
        XCTAssertTrue(eventNameField.waitForExistence(timeout: 5), "Event editor should open")
        KeyboardAvoidanceTestSupport.replaceText(in: eventNameField, with: "Lap")
        KeyboardAvoidanceTestSupport.tapToolbarAction("Save", in: app)

        // Back in the batch editor. Save the batch (persists it), which dismisses
        // back to the batch list.
        app.buttons["batch-save-button"].tap()

        // Reopen the batch from the batch list and verify the event name persisted.
        let swimBatchAgain = app.staticTexts["Swim"]
        XCTAssertTrue(swimBatchAgain.waitForExistence(timeout: 5), "Batch list should show Swim after dismissing")
        swimBatchAgain.tap()

        let eventCellAgain = app.cells.firstMatch
        XCTAssertTrue(eventCellAgain.waitForExistence(timeout: 5), "Batch editor should reopen")
        eventCellAgain.tap()

        let eventNameFieldAgain = app.textFields["event-name-field"]
        XCTAssertTrue(eventNameFieldAgain.waitForExistence(timeout: 5), "Event editor should reopen")
        XCTAssertEqual(eventNameFieldAgain.value as? String, "Lap", "Event name should be persisted")
    }

    @MainActor
    func testTappingExistingEventOpensEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestNameAutosaveSeconds", "0"]
        app.launch()

        openCalendarsList(app)
        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        let day1 = dayIdentifier(day: 1)
        app.descendants(matching: .any).matching(identifier: day1).firstMatch.tap()
        let womenCycle = app.staticTexts["Women Cycle"]
        XCTAssertTrue(womenCycle.waitForExistence(timeout: 5), "Batch list should show Women Cycle")
        womenCycle.tap()

        let eventCell = app.cells.firstMatch
        XCTAssertTrue(eventCell.waitForExistence(timeout: 5), "Batch editor should list the event")
        eventCell.tap()

        XCTAssertTrue(app.textFields["event-name-field"].waitForExistence(timeout: 5), "Event editor should open")
    }
}
