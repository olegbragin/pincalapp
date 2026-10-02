//
//  MultiselectAndDefaultsTests.swift
//  PinCalAppUITests
//
//  Three reported behaviours, each encoded as a UI test. Written before the fixes, so
//  every one of them is expected to fail on the current build — a test that passes against
//  the broken behaviour is worse than no test.
//

import XCTest

final class MultiselectAndDefaultsTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let day = 20

    /// Launches the seeded app and opens the calendar detail.
    ///
    /// Returns the instance it launched rather than letting each test make its own: an
    /// `XCUIApplication` that was never `launch()`ed has no window, and a test holding one
    /// of those while a *different* instance is the one on screen fails for reasons that
    /// have nothing to do with the behaviour under test.
    @MainActor
    private func openSeededCalendar() -> XCUIApplication {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        return app
    }

    // MARK: - 1. A tapped day in a multi-select session takes the selected colour

    /// STR: open a calendar, press Multiselect, pick a colour, tap a day.
    ///
    /// AB: the tap only toggles the colour picker's disabled state; the day is never
    /// marked. EB: the day is selected and marked with the chosen colour, and the picker is
    /// disabled once any day is selected.
    ///
    /// The assertion is about the day being *marked*, because that is the observable
    /// consequence of "set with the selected colour" that accessibility can see — the day
    /// cell's label is `"<n>, <k> events"` and carries no colour name.
    @MainActor
    func testMultiselectDayTapMarksTheDayWithTheSelectedColour() throws {
        let app = openSeededCalendar()

        let multiselect = KeyboardAvoidanceTestSupport.toolbarAction("Multiselect", in: app)
        XCTAssertTrue(multiselect.waitForExistence(timeout: 5), "Multiselect button should be visible")
        multiselect.tap()

        let colour = app.buttons["color-option-eventColorOption2"]
        XCTAssertTrue(colour.waitForExistence(timeout: 5), "The colour picker should be visible in a session")
        colour.tap()

        // With no day selected the picker must still be usable.
        XCTAssertTrue(colour.isEnabled, "Picking a colour is what arms the session; the picker starts enabled")

        let dayID = KeyboardAvoidanceTestSupport.dayIdentifier(day: day)
        let cell = app.descendants(matching: .any).matching(identifier: dayID).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Day \(day) should be on the calendar")
        XCTAssertFalse(
            cell.label.lowercased().contains("event"),
            "Day \(day) starts empty; label = \(cell.label)"
        )

        cell.tap()

        // The point of the report: tapping a day marks it, in the session's colour.
        XCTAssertTrue(
            cell.waitForNonExistence(timeout: 1) || cell.label.lowercased().contains("event"),
            "Day \(day) must be marked after being tapped in a multi-select session; label = \(cell.label)"
        )
        XCTAssertTrue(
            cell.label.lowercased().contains("event"),
            "Day \(day) should be marked with the selected colour; label = \(cell.label)"
        )

        // …and the picker locks once a day is in the session, so it cannot be changed
        // under a selection that was made in one colour.
        XCTAssertFalse(
            colour.isEnabled,
            "With a day selected the picker must be disabled, so a selection cannot be made in two colours"
        )
    }

    // MARK: - 2. Saving a confirmed session returns to the calendar, not the calendar list

    /// STR: the above, then confirm, name the batch, save.
    ///
    /// AB: the batch persists but the user is dropped on the calendars list. EB: the user
    /// is back on the single calendar view.
    ///
    /// The calendar detail is not a navigation-stack entry — `RootNavigation` shows it
    /// through `detailCalendarID` and a compact-column preference — so "are we on the
    /// calendar" is asked of the *day cells*, which exist on the calendar and nowhere else.
    /// A back button would be weaker: the calendars list has one too.
    @MainActor
    func testSavingAConfirmedMultiselectSessionReturnsToTheCalendar() throws {
        let app = openSeededCalendar()

        KeyboardAvoidanceTestSupport.tapToolbarAction("Multiselect", in: app)
        let colour = app.buttons["color-option-eventColorOption2"]
        XCTAssertTrue(colour.waitForExistence(timeout: 5), "The colour picker should be visible in a session")
        colour.tap()
        KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)

        // Confirm: in a session the toolbar button reads "Save".
        let confirm = KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Toolbar should offer Save during a session")
        confirm.tap()

        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Confirming should open the batch editor")
        KeyboardAvoidanceTestSupport.replaceText(in: nameField, with: "Pair")

        let batchSave = app.buttons["batch-save-button"]
        XCTAssertTrue(batchSave.isEnabled, "A coloured, named batch must be savable")
        batchSave.tap()
        XCTAssertTrue(batchSave.waitForNonExistence(timeout: 3), "Batch editor should dismiss after Save")

        let dayID = KeyboardAvoidanceTestSupport.dayIdentifier(day: day)
        let cell = app.descendants(matching: .any).matching(identifier: dayID).firstMatch
        XCTAssertTrue(
            cell.waitForExistence(timeout: 5),
            "After saving a confirmed session the user should be back on the single calendar view, not the calendars list"
        )
        XCTAssertTrue(
            cell.label.lowercased().contains("event"),
            "and the saved day must be marked; label = \(cell.label)"
        )
    }

    // MARK: - 3. A new batch and its event arrive ready to save

    /// STR: open a calendar, tap a day with no events.
    ///
    /// AB: the editor shows an empty name and a grey picker, so Save is disabled. EB: the
    /// batch arrives named "New event" with the first colour already selected, and its
    /// event arrives named "New event day" in the batch's colour.
    @MainActor
    func testANewBatchArrivesNamedAndColoured() throws {
        let app = openSeededCalendar()

        KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)

        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Batch editor should open for an empty day")
        XCTAssertEqual(
            nameField.value as? String, "New event",
            "A new batch should arrive with a default name rather than an empty field"
        )

        let picker = app.buttons["color-picker-compact"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "The batch colour picker should be visible")
        let value = (picker.value as? String) ?? ""
        XCTAssertFalse(
            value.isEmpty,
            "A new batch should arrive with a colour already selected rather than a grey picker"
        )

        let batchSave = app.buttons["batch-save-button"]
        XCTAssertTrue(batchSave.isEnabled, "So the batch must be savable without the user doing anything")

        // The event inherits the batch's colour and gets its own default name.
        let eventRow = app.collectionViews.buttons
            .containing(NSPredicate(format: "label CONTAINS %@", "at"))
            .firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "The batch should list its placeholder event")
        eventRow.tap()

        let eventName = app.textFields["event-name-field"]
        XCTAssertTrue(eventName.waitForExistence(timeout: 5), "Event editor should open")
        XCTAssertEqual(
            eventName.value as? String, "New event day",
            "A new event should arrive with a default name rather than an empty field"
        )
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.toolbarAction("Save", in: app).isEnabled,
            "So the event must be savable without the user doing anything"
        )
    }
}
