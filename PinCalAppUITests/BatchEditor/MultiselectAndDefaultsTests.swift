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
    func testMultiselectDayTapMarksTheDayWithTheSelectedColour() {
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
    func testSavingAConfirmedMultiselectSessionReturnsToTheCalendar() {
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

        // Confirming ends the session and opens the batch editor on what it built.
        //
        // **Premise changed.** This asserted `batch-name-field` does *not* exist — "Confirming
        // should not open the batch editor" — on the reasoning that the days were written as
        // they were tapped, leaving nothing to commit. They are not written as they are tapped
        // any more: an unnamed batch is a draft, so the session's days exist only as a
        // selection, and this editor is where the batch becomes a batch.
        //
        // It had opened an editor once before, as a review step over data that was already
        // durable. That was a review step with nothing to review; this one has a name to ask
        // for.
        let batchNameField = app.textFields["batch-name-field"]
        XCTAssertTrue(
            batchNameField.waitForExistence(timeout: 5),
            "Confirming a session should open the batch editor on its batch"
        )
        // Name it, then leave: the editor is where the draft becomes real, and the calendar
        // underneath is what the rest of this test is about.
        KeyboardAvoidanceTestSupport.replaceText(in: batchNameField, with: "Morning")
        let editorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(editorBack.waitForExistence(timeout: 5))
        editorBack.tap()
        XCTAssertTrue(
            editorBack.waitForNonExistence(timeout: 5),
            "leaving the editor should dismiss it"
        )
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.waitForToolbarAction("Multiselect", in: app),
            "and should leave the calendar in single-select mode"
        )

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
    /// event is already listed wearing that colour.
    ///
    /// The event's *name* used to be part of this claim, read off the event editor's own field
    /// ("New event day"). The editor is gone, so the tail asserts the row exists instead — the
    /// same "the batch arrives holding a placeholder event" fact, from the screen that lists it.
    @MainActor
    func testANewBatchArrivesNamedAndColoured() {
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

        let batchEditorBack = app.buttons["batch-editor-back-button"]
        XCTAssertTrue(batchEditorBack.isEnabled, "So the batch must be savable without the user doing anything")

        // The event inherits the batch's colour and gets its own default name.
        //
        // **Premise changed.** This opened the event editor and asserted its name field held
        // "New event day", then that its Back was enabled. Both are gone with the screen. What
        // survives is the part that is still observable from here: the row exists, which is the
        // same claim — the batch arrives holding a placeholder event — read off the one screen
        // that lists them. By index: a row's text is a formatted timestamp, whose wording is
        // the locale's.
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.eventRow(0, in: app).waitForExistence(timeout: 5),
            "The batch should list its placeholder event"
        )
    }
}
