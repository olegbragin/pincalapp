//
//  ClosingTheSelectedCalendarTests.swift
//  PinCalAppUITests
//
//  Archiving or permanently deleting the calendar that is on screen must clear the selection.
//
//  Left stale, `detailCalendarID` names a calendar that is no longer there, and the app root
//  goes on injecting that calendar's store.
//
//  ## Where this is observable, and where it is not
//
//  **Only on a pad**, and the test is bracketed to say so rather than pretending otherwise.
//
//  On a phone in compact width the split view collapses to one column, so backing out of a
//  calendar removes its detail from the hierarchy whatever the id says. A test asserting "the
//  detail is gone" there passes with the bug present — it was written that way first, and it
//  was green against code that closed nothing, which is the failure mode this file exists to
//  avoid.
//
//  On a pad the detail column is a *peer* of the content column and stays on screen. That is
//  where a stale id is visible: the detail keeps rendering a calendar that has left the active
//  set, and for a deleted one it renders **nothing at all** — `SingleCalendarModel` fetches,
//  finds no calendar, and `.empty` draws an `EmptyView`. A blank column with a live navigation
//  bar and no way back.
//
//  So the assertion is the placeholder that replaces it: `RootDetailView` shows "Select a
//  calendar" when the id is nil, and the calendar's own grid when it is not.
//

import XCTest

@MainActor
final class ClosingTheSelectedCalendarTests: XCTestCase {

    /// The seeded calendar. Id 1 — see `TestDataSeeder`.
    private let calendarID: Int64 = 1
    private let calendarName = "UI Test Calendar"

    /// The detail's own identifier, which is what "the selection is still this calendar"
    /// looks like from the outside.
    ///
    /// Preferred over asserting on the grid's day cells: those exist in the batch editor too,
    /// so they answer a weaker question than the one being asked here.
    private func detail(_ id: Int64, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "calendar-detail-\(id)").firstMatch
    }

    /// "Select a calendar" — `RootDetailView`'s placeholder, and the only thing on screen that
    /// means "no calendar is selected".
    ///
    /// Asserted *alongside* the disappearance rather than instead of it: the detail going away is
    /// the mechanism, and a screen that had simply crashed would satisfy it too.
    private func placeholder(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["Select a calendar"]
    }

    /// Launch arguments in a method rather than in `setUp`, because an override of
    /// `setUpWithError` is not main-actor isolated even on a `@MainActor` class — and touching
    /// `XCUIApplication` from there is a warning that would otherwise be here forever.
    private func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSeedData",
            "-UITestColumns", "1",
            "-UITestNameAutosaveSeconds", "0",
            // Long, so the toast is simply *there* for the whole test rather than something a
            // 5-second window has to be lucky to catch. Production is untouched.
            "-UITestUndoWindowSeconds", "120",
        ]
        app.launch()
        return app
    }

    /// Opens the seeded calendar and leaves it on screen, with the list still beside it.
    @discardableResult
    private func openCalendarKeepingTheListVisible(_ app: XCUIApplication) -> Bool {
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: calendarName)
        return detail(calendarID, in: app).waitForExistence(timeout: 20)
    }

    /// Skips on a phone, and says why rather than passing vacuously.
    private func requireWideLayout(_ app: XCUIApplication) throws {
        guard KeyboardAvoidanceTestSupport.isPad(app) else {
            throw XCTSkip(
                """
                A stale selection is not observable on a phone: compact width collapses the \
                split view, so the detail leaves the hierarchy on Back whether or not the id was \
                cleared. Asserting it here would pass against the bug. The state itself is \
                covered by AppNavigationTests, and this is covered by the pad profile.
                """
            )
        }
    }

    func testArchivingTheSelectedCalendarClosesIt() throws {
        let app = launchSeededApp()
        XCTAssertTrue(
            openCalendarKeepingTheListVisible(app),
            "The seeded calendar's detail should be on screen"
        )
        try requireWideLayout(app)

        // Archiving happens from the card, which lives in the content column — a peer of the
        // detail on a pad, so it is reachable without leaving the calendar. The button carries
        // its calendar's id, so there is nothing to guess about which card this archives.
        let archive = app.buttons["card-archive-\(calendarID)"]
        XCTAssertTrue(
            archive.waitForExistence(timeout: 10),
            "The calendar's card should offer archive while its detail is on screen"
        )
        archive.tap()

        XCTAssertTrue(
            detail(calendarID, in: app).waitForNonExistence(timeout: 15),
            """
            Archiving the calendar that is on screen must close it. The detail is still \
            calendar-detail-\(calendarID), so the app root is still injecting a store for a \
            calendar that has left the active set.
            """
        )
        XCTAssertTrue(
            placeholder(in: app).waitForExistence(timeout: 5),
            "and what replaces it says so, rather than the column going blank"
        )
    }

    /// Archiving is undoable, and Undo is the user's way back. If the close left them somewhere
    /// they cannot act from, the escape hatch is unreachable too — which is the difference
    /// between "the selection was cleared" and "the app is still usable".
    ///
    /// The restore is published as a *change*, not a delete, so it does not reopen the detail:
    /// the calendar comes back to the list, and selecting it again is the user's decision. A
    /// detail that reappeared on its own would be the app deciding what the user is looking at.
    func testTheClosedCalendarCanBeUndoneFromWhereTheUserLands() throws {
        let app = launchSeededApp()
        XCTAssertTrue(
            openCalendarKeepingTheListVisible(app),
            "The seeded calendar's detail should be on screen"
        )
        try requireWideLayout(app)

        app.buttons["card-archive-\(calendarID)"].tap()
        XCTAssertTrue(
            detail(calendarID, in: app).waitForNonExistence(timeout: 15),
            "precondition: the calendar is closed"
        )

        // Where did the user land? Asserted by what they can *do* rather than by which column
        // is showing, because the column layout is the system's business and this test is about
        // the app not stranding anyone.
        let undo = app.descendants(matching: .any)
            .matching(identifier: "archive-undo-toast-button").firstMatch
        XCTAssertTrue(
            undo.waitForExistence(timeout: 10),
            "The undo toast must be reachable from wherever the close left the user"
        )
        undo.tap()

        XCTAssertTrue(
            app.staticTexts[calendarName].waitForExistence(timeout: 15),
            "Undoing the archive should put the calendar back in the active list"
        )
        XCTAssertFalse(
            detail(calendarID, in: app).exists,
            "and it must come back to the list rather than reopening itself in the detail column"
        )
    }
}