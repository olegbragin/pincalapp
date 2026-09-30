//
//  CalendarSeedPresenceTests.swift
//  PinCalAppUITests
//
//  Does the seed data actually arrive?
//
//  Every iPad failure in this area reported the same four words — *"Day cell … should
//  exist"* — and that message cannot distinguish four different causes: no calendar at all,
//  a calendar showing a different month, a grid that never built, or a query that cannot
//  match what is there. `tapDay` now reports an inventory when it fails, and that inventory
//  said `dayCells=0` on the iPad: not the wrong day, **no day cells at all**.
//
//  That has an obvious candidate the suite never checked, because it had no way to: the
//  seed data never arrived. The AutoTestRunner erases the simulator before every run, so the
//  app launches against an empty store, and `-UITestSeedData` is the only thing standing
//  between that and an empty list. If seeding is not honoured on some form factor, every
//  test that assumes a seeded calendar fails for a reason that has nothing to do with the
//  feature under test.
//
//  So this test asks the question directly instead of inferring it, and — because a test
//  that only diagnoses is not much use to the next person — it also establishes a calendar
//  the hard way when there is none.
//

import XCTest

@MainActor
final class CalendarSeedPresenceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()
        return app
    }

    private func emptyActiveList(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "calendar-list-empty-active").firstMatch
    }

    /// Creates a calendar through the UI, using nothing but identifiers.
    ///
    /// The whole point of the identifiers added alongside this test: the plus button is a
    /// bare `plus` glyph, the sheet's controls are localised strings, and a test that had to
    /// find any of them by label or by position would be at the mercy of the copy and the
    /// layout. Each step here is a stable name.
    @discardableResult
    private func createCalendar(named name: String, in app: XCUIApplication) -> Bool {
        let add = app.descendants(matching: .any).matching(identifier: "calendar-list-add-button").firstMatch
        guard add.waitForExistence(timeout: 5) else {
            XCTFail("The calendar list's add button should exist")
            return false
        }
        add.tap()

        // The name field is the sentinel for "the sheet opened" — *not* the sheet's root.
        // The root deliberately carries no identifier: putting one there overrides the
        // identifiers of everything inside it, which is what hid the save button in the
        // first place. A leaf control is both safer to key on and more precise about what it
        // is asserting.
        let field = app.descendants(matching: .any)
            .matching(identifier: "add-calendar-name-field").firstMatch
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Tapping add should present the add-calendar sheet with a name field")
            return false
        }
        KeyboardAvoidanceTestSupport.replaceText(in: field, with: name)

        let save = app.descendants(matching: .any)
            .matching(identifier: "add-calendar-save-button").firstMatch
        if !save.exists {
            // Just the buttons. A full descendant enumeration is itself unreliable
            // here — it failed on "No matches found for Element at index 140", because
            // the tree changes under the walk — and a diagnostic that crashes is no
            // diagnostic at all.
            let buttons = app.buttons.allElementsBoundByIndex
                .map { "\($0.identifier)|\($0.label)" }.joined(separator: " ~ ")
            XCTFail("save button absent. Buttons: " + buttons)
            return false
        }
        save.tap()
        return app.staticTexts[name].waitForExistence(timeout: 10)
    }

    /// The seeded calendar is on the list, and opening it renders a day grid.
    ///
    /// Both halves, because they are different questions and the first one was previously
    /// mistaken for the whole. The list being populated only proves the seed arrived; what
    /// the iPad failures actually showed was `dayCells=0` *after* the calendar was opened,
    /// so the grid is the part that needs proving.
    func testSeededCalendarIsPresentAndItsGridRenders() {
        let app = launch()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)

        if emptyActiveList(in: app).waitForExistence(timeout: 5) {
            XCTFail("""
                The active calendar list is EMPTY on this device, so no test that assumes a \
                seeded calendar can pass here. `-UITestSeedData` is not reaching the store.
                """)
            return
        }

        XCTAssertTrue(
            app.staticTexts["UI Test Calendar"].waitForExistence(timeout: 15),
            "The seeded calendar should be listed; the list is neither seeded nor empty-state"
        )

        app.staticTexts["UI Test Calendar"].firstMatch.tap()

        // The grid, asked for directly. `tapDay`'s inventory turns a failure here into a
        // statement about what *is* on screen, which is the only thing that moved this
        // investigation forward.
        let anyDay = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "day-"))
            .firstMatch
        if !anyDay.waitForExistence(timeout: 20) {
            let present = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "day-"))
                .allElementsBoundByIndex.map(\.identifier)
            let statics = app.staticTexts.allElementsBoundByIndex.prefix(12)
                .map { $0.label }.joined(separator: " | ")
            XCTFail("""
                Opening the seeded calendar rendered no day grid. dayCells=\(present.count). \
                Visible text: \(statics)
                """)
            return
        }
        XCTAssertTrue(anyDay.exists, "The calendar should render its day grid once opened")
    }

    /// A calendar created through the UI reaches the list and opens a day grid.
    ///
    /// Independent of seeding, so it answers the other half of the question: is the create
    /// route itself working on this form factor? If this passes while the test above fails,
    /// the list and the create route are fine and the fault is in seeding alone.
    func testCalendarCreatedThroughTheUIOpensItsDayGrid() {
        let app = launch()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)

        XCTAssertTrue(
            createCalendar(named: "Handmade", in: app),
            "Creating a calendar through the UI should add it to the list"
        )

        app.staticTexts["Handmade"].firstMatch.tap()

        let anyDay = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "day-"))
            .firstMatch
        XCTAssertTrue(
            anyDay.waitForExistence(timeout: 15),
            "A calendar opened from the list should render its day grid"
        )
    }
}
