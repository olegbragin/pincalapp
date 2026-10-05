//
//  RestoresLastSelectedCalendarTests.swift
//  PinCalAppUITests
//
//  Relaunching the app reopens the calendar that was on screen.
//
//  ## What is and is not observable here
//
//  **The round trip across two launches is not, and that is not an oversight.** Every seeded launch
//  points the calendar store at a fresh temporary directory (`UITestStoreFactory`), so each launch
//  is a *different database* whose ids start at 1 again. A calendar selected in one launch cannot
//  still exist in the next one, so "select, relaunch, still selected" is not a question this app
//  can be asked under a seed. The write and the read are covered as a pair over one real store by
//  `PCAppSessionTests`; what this file adds is that the restore reaches the *screen*, which is the
//  part that can break in wiring no unit test can see.
//
//  So the remembered calendar is seeded by launch argument, and everything after it — the read, the
//  validation, the switch — is the production path.
//

import XCTest

/// The restore is asserted through `calendar-detail-<id>`, the detail's own identifier, and so is
/// what "this calendar is the one on screen" looks like from the outside. Preferred over the grid's
/// day cells, which also exist in the batch editor and would answer a weaker question.
///
/// Two seeded calendars are named throughout, and **each test asserts the other is absent**. That
/// is what makes these falsifiable. Preferences are not reset between launches, so every test in this
/// class leaves a remembered id behind — and since the seed always produces the same three ids, a
/// test that only asserted "some detail is on screen" would pass just as happily on the previous
/// test's leftover. Asking for a *different* calendar and requiring the other one to be gone means
/// only the launch argument can explain what came up.
@MainActor
final class RestoresLastSelectedCalendarTests: XCTestCase {
    /// "UI Test Calendar" — id 1 in a freshly seeded store. See `TestDataSeeder`.
    private let firstID: Int64 = 1
    /// "Third Calendar" — id 3. Picked over "Second Calendar" because it has no batches, so its
    /// detail is the cheapest one to bring up.
    private let thirdID: Int64 = 3

    private func launch(remembering id: Int64?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSeedData",
            "-UITestColumns", "1",
            "-UITestNameAutosaveSeconds", "0",
        ]
        if let id {
            // Seeds the remembered selection, which is then read back through the ordinary path.
            app.launchArguments += ["-UITestSelectedCalendar", String(id)]
        }
        app.launch()
        return app
    }

    private func detail(_ id: Int64, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "calendar-detail-\(id)").firstMatch
    }

    /// `RootDetailView`'s placeholder, and the only thing on screen that means "nothing is selected".
    ///
    /// **Pad only**, and asking for it on a phone is a mistake worth recording: compact width
    /// renders one column at a time and lands on the list, so at launch the detail column is not in
    /// the hierarchy at all and this element cannot exist however the app was launched. It would be
    /// absent for the wrong reason and read as "nothing was selected" when it only means "nothing is
    /// on this screen". `ClosingTheSelectedCalendarTests` records the same asymmetry.
    private func placeholder(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["Select a calendar"]
    }

    /// The calendar the launch named is open, and the other one is not.
    ///
    /// Runs on both idioms. On a pad the detail column is a peer of the list, so a selected calendar
    /// is on screen without navigating anywhere. On a phone the restore also turns the split view
    /// to the detail column, so the same element appears — by a different route, which is why this
    /// file asserts existence and nothing about what is behind it.
    func testTheRememberedCalendarIsOpenOnLaunch() {
        let app = launch(remembering: firstID)

        XCTAssertTrue(
            detail(firstID, in: app).waitForExistence(timeout: 20),
            """
            The app opened on the calendar it was told to remember, without a tap. \
            calendar-detail-\(firstID) should be on screen at launch.
            """
        )
        XCTAssertFalse(
            detail(thirdID, in: app).exists,
            "and only that one — a leftover from an earlier launch would satisfy the assertion above"
        )
    }

    /// The same feature, asked for a *different* calendar.
    ///
    /// Separate from the test above rather than a parameter, because the pair is the assertion: the
    /// previous test leaves `firstID` stored, so if this one came up showing `firstID` it would mean
    /// the launch argument is ignored and the stored value wins. Running the two in either order
    /// gives the same answer, which is what makes it independent of XCTest's ordering.
    func testTheCalendarTheLaunchNamedIsTheOneThatOpens() {
        let app = launch(remembering: thirdID)

        XCTAssertTrue(
            detail(thirdID, in: app).waitForExistence(timeout: 20),
            "calendar-detail-\(thirdID) should be the one on screen at launch"
        )
        XCTAssertFalse(
            detail(firstID, in: app).exists,
            "the launch argument decides, not whichever id an earlier run left stored"
        )
    }

    /// The detail is a rendered calendar, not an element that happens to carry the identifier.
    ///
    /// The identifier is set by the same view that builds the grid, so this is mostly a guard against
    /// the assertions above being satisfied by something that is not the calendar.
    func testTheRememberedCalendarHasRenderedItsGrid() {
        let app = launch(remembering: firstID)
        XCTAssertTrue(
            detail(firstID, in: app).waitForExistence(timeout: 20),
            "precondition: the detail is on screen"
        )

        let grid = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "day-"))
            .firstMatch

        XCTAssertTrue(
            grid.waitForExistence(timeout: 20),
            "A detail that rendered empty would satisfy the identifier assertion on its own"
        )
    }

    /// A seeded relaunch reopens nothing, **with a remembered calendar definitely stored**.
    ///
    /// The premise is arranged inside the test rather than left to test ordering: the first launch
    /// restores a calendar, which is what writes the remembered id, and the second launch reads that
    /// same stored id and must still open nothing. Written as two separate tests this could not be
    /// guaranteed — alphabetically this one runs *first*, so "a previous test left a key behind"
    /// would have been false, and the assertion would have been passing because the key was absent.
    /// That is the failure `AGENTS.md` calls a test that cannot fail wearing a passing test's
    /// clothes, and it is why this is one method with two launches.
    ///
    /// The gate is keyed off the seeding flag because that flag already means "this is a throwaway
    /// database": a remembered id from another database is not stale there, it is meaningless. And
    /// restoring it would be actively harmful — on a phone it drops the user into the detail column
    /// instead of the list, which is enough to strand every test in the suite that starts by tapping
    /// a sidebar row.
    func testASeededRelaunchReopensNothingEvenWithACalendarRemembered() {
        let app = launch(remembering: firstID)
        XCTAssertTrue(
            detail(firstID, in: app).waitForExistence(timeout: 20),
            """
            precondition: the first launch restored, and restoring is what writes the remembered \
            id — so the relaunch below is reading a real stored value, not an absent one.
            """
        )

        app.terminate()
        let relaunched = launch(remembering: nil)

        // What "the launch resolved to nothing selected" looks like is the idiom's business, so
        // each is asked its own question and the assertion that follows is the one that means the
        // same thing on both.
        if KeyboardAvoidanceTestSupport.isPad(relaunched) {
            XCTAssertTrue(
                placeholder(in: relaunched).waitForExistence(timeout: 20),
                "A pad shows the detail column beside the list, so nothing selected has to say so"
            )
        } else {
            XCTAssertTrue(
                relaunched.staticTexts["UI Test Calendar"].firstMatch.waitForExistence(timeout: 20),
                "A phone should land on the calendar list rather than inside a calendar"
            )
        }

        XCTAssertFalse(
            detail(firstID, in: relaunched).exists,
            "a remembered id from a different database must not be reopened on this one"
        )
    }
}
