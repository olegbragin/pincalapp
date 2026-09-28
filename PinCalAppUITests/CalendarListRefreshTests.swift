//
//  CalendarListRefreshTests.swift
//  PinCalAppUITests
//
//  Pull-to-refresh on the calendar list.
//
//  `CalendarListContent` attaches plain `.refreshable`, wired to
//  `CalendarListViewModel.fetch()`. The batch-assembly refactor changed that method:
//  it now assigns `calendars` straight from `CalendarCache.loadedCalendars()` rather
//  than waiting for the `.refresh` broadcast it had just triggered itself. So the
//  failure mode these tests guard is no longer "the list never loads" — it is "a
//  refresh clobbers, duplicates, or resurrects rows".
//
//  What these tests can and cannot prove: the UI-test store is seeded in memory at
//  launch and nothing writes to it out of band, so a refresh can never surface *new*
//  data. The assertions are therefore about convergence — the rendered list matches the
//  store exactly, one card per calendar — and about a refresh landing on top of live
//  list state. `testRefreshDoesNotResurrectAnArchivedCalendar` is the one that would
//  catch a `fetch()` reading the wrong source.
//

import XCTest

@MainActor
final class CalendarListRefreshTests: XCTestCase {

    private let seededNames = ["UI Test Calendar", "Second Calendar", "Third Calendar"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func openSeededCalendarsList() -> XCUIApplication {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarsList(app)
        XCTAssertTrue(
            calendar(named: seededNames[0], in: app).waitForExistence(timeout: 15),
            "The seeded calendar list should load. Saw: \(visibleCalendarNames(in: app))"
        )
        return app
    }

    /// Polls with a real yield between attempts. A blocking `XCTWaiter` would stall the
    /// main-actor work it is waiting on; a busy poll would starve it. Same shape as the
    /// wait the keyboard suite already uses.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func calendar(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts[name].firstMatch
    }

    /// How many elements render this calendar's name. Cards carry no identifier at rest:
    /// `card-name-field-<id>` exists only while a card is being renamed, so it cannot
    /// count resting cards.
    private func copies(of name: String, in app: XCUIApplication) -> Int {
        app.staticTexts.matching(NSPredicate(format: "label == %@", name)).count
    }

    private func visibleCalendarNames(in app: XCUIApplication) -> [String] {
        let known = seededNames.filter { copies(of: $0, in: app) > 0 }
        return known.isEmpty ? ["<none of the seeded names>"] : known
    }

    private func assertSeededCalendarsPresent(_ app: XCUIApplication) {
        for name in seededNames {
            XCTAssertEqual(
                copies(of: name, in: app), 1,
                "'\(name)' should appear exactly once. Visible: \(visibleCalendarNames(in: app))"
            )
        }
    }

    /// The card's own archive button. Every card exposes one with the same identifier,
    /// so it is picked by proximity to the calendar's name rather than by position, which
    /// keeps the pairing correct if the list ever re-sorts.
    private func trashButton(for name: String, in app: XCUIApplication) -> XCUIElement {
        let targetMidY = calendar(named: name, in: app).frame.midY
        let trashes = app.buttons.matching(identifier: "trash")
        XCTAssertGreaterThanOrEqual(trashes.count, 1, "Cards should each expose a trash button")
        return trashes.allElementsBoundByIndex.min {
            abs($0.frame.midY - targetMidY) < abs($1.frame.midY - targetMidY)
        } ?? trashes.firstMatch
    }

    /// Performs a real pull on the grid.
    ///
    /// A coordinate press-drag, **not** `swipeDown`. Measured on iOS 27: `swipeDown` on
    /// the grid does not trigger `.refreshable` at all — it was silently a no-op, and a
    /// test built on it passes whether or not refresh works. A press inside the grid
    /// dragged below its bottom edge, held, then released, does fire it. That
    /// distinction is why this helper exists rather than a one-liner.
    private func pullToRefresh(_ app: XCUIApplication) {
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "The calendar grid should be on screen")
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let beyondBottom = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
        start.press(
            forDuration: 0.1,
            thenDragTo: beyondBottom,
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
    }

    private func archive(_ name: String, in app: XCUIApplication) {
        trashButton(for: name, in: app).tap()
    }

    /// The sidebar rows surface as `StaticText`/`Image` with the identifier, not as
    /// buttons, so a plain `app.buttons[...]` query finds nothing.
    private func openArchivedList(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists {
            back.tap()
        }
        let archived = app.descendants(matching: .any).matching(identifier: "sidebar-archived").firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5), "The sidebar should offer Archived")
        archived.tap()
    }

    // MARK: - Tests

    /// The baseline case: a pull over an untouched list leaves exactly the seeded rows,
    /// one card each.
    ///
    /// There is deliberately no spinner assertion. `CalendarListView` renders its
    /// loading state only when `calendars.isEmpty`, so with a populated list it can
    /// never appear — checking for it would assert nothing.
    func testPullToRefreshKeepsSeededCalendarsIntact() {
        let app = openSeededCalendarsList()
        assertSeededCalendarsPresent(app)

        pullToRefresh(app)

        // The refresh is async and the grid re-lays out; give it room before asserting.
        // A row that survived it wrong — duplicated, dropped, mid-transition — is still
        // wrong once the grid settles.
        XCTAssertTrue(calendar(named: seededNames[0], in: app).waitForExistence(timeout: 10))
        assertSeededCalendarsPresent(app)
    }

    /// The load-bearing one. Archiving removes a row through the change feed, then a
    /// refresh re-reads the calendar. If `fetch()` read the wrong source — every
    /// calendar rather than the active ones — the archived row would come back.
    func testRefreshDoesNotResurrectAnArchivedCalendar() async {
        let app = openSeededCalendarsList()
        archive(seededNames[0], in: app)

        await waitUntil { self.copies(of: self.seededNames[0], in: app) == 0 }
        XCTAssertEqual(copies(of: seededNames[0], in: app), 0,
                       "Archiving should remove the card from the active list")

        pullToRefresh(app)

        XCTAssertEqual(copies(of: seededNames[0], in: app), 0,
                       "A refresh must not bring an archived calendar back into the active list")
        XCTAssertEqual(copies(of: seededNames[1], in: app), 1)
        XCTAssertEqual(copies(of: seededNames[2], in: app), 1)
    }

    /// The archived list takes the other branch of `fetch()`: `loadArchived` rather than
    /// `loadActive`. A refresh there must show the archived calendar and only it.
    func testRefreshInArchivedModeShowsOnlyArchivedCalendars() async {
        let app = openSeededCalendarsList()
        archive(seededNames[0], in: app)
        await waitUntil { self.copies(of: self.seededNames[0], in: app) == 0 }

        openArchivedList(app)

        XCTAssertTrue(
            calendar(named: seededNames[0], in: app).waitForExistence(timeout: 15),
            "The archived calendar should appear under Archived. Saw: \(visibleCalendarNames(in: app))"
        )
        XCTAssertEqual(copies(of: seededNames[1], in: app), 0, "An active calendar must not appear under Archived")
        XCTAssertEqual(copies(of: seededNames[2], in: app), 0, "An active calendar must not appear under Archived")

        pullToRefresh(app)

        XCTAssertEqual(copies(of: seededNames[0], in: app), 1, "The archived calendar should survive a refresh")
        XCTAssertEqual(copies(of: seededNames[1], in: app), 0)
        XCTAssertEqual(copies(of: seededNames[2], in: app), 0)
    }
}
