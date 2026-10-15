//
//  EmptyDayTapMarkerTests.swift
//  PinCalAppUITests
//
//  STR: open a calendar, tap a day that has no events on it.
//
//  AB: the batch editor opens with the tapped day **unmarked** in its calendar.
//  EB: the tapped day is marked in the batch editor's calendar.
//
//  And then, leaving an untouched one takes the marker away again — which is the behaviour
//  this test was last rewritten to assert the *opposite* of, and is now correct again.
//
//  That half has been inverted twice. It first said a marker surviving Back was a phantom,
//  because tapping a day staged an edit nothing had written. Then it said the opposite: the
//  tap wrote the batch, so the marker was real and Back should not unmake it. Now a tapped
//  day is a *draft* — staged, coloured, marked, and not written — so nothing survives a Back
//  that changed nothing, and nothing should.
//
//  The two faults are still not the same bug. The editor showing nothing is a projection
//  never recomputed when the assembly was staged; a marker outliving a discarded assembly is
//  the same projection not recomputed when the assembly is thrown away.
//

import XCTest

final class EmptyDayTapMarkerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openSeededCalendar() -> XCUIApplication {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        return app
    }

    /// The first day in `candidates` that is genuinely empty.
    ///
    /// Picked by observation rather than hard-coded. The seeded calendar's events move
    /// whenever seed data changes, and a test that hard-codes a day and then asserts the day
    /// is empty fails on the fixture, not on the behaviour.
    @MainActor
    private func firstEmptyDay(in app: XCUIApplication, from candidates: [Int]) throws -> Int {
        for day in candidates {
            let cell = KeyboardAvoidanceTestSupport.dayCell(day: day, in: app)
            guard cell.waitForExistence(timeout: 2) else { continue }
            if !cell.label.lowercased().contains("event") {
                return day
            }
        }
        XCTFail("None of the candidate days \(candidates) was empty; the seed data changed")
        throw XCTSkip("no empty day available")
    }

    /// A tapped empty day is marked while the editor is open, and the marker goes when the
    /// user leaves without having done anything with it — because nothing was written.
    ///
    /// Both halves are asserted, because a draft marked only *after* being written would be
    /// the same fault wearing the opposite sign: the editor claiming a day it has not
    /// committed. The second half is the one that carries the guarantee — this is the
    /// misclick, and its whole cost is that it used to leave a row in the database that no
    /// undo could reach.
    @MainActor
    func testTappingEmptyDayMarksItInBatchEditorAndLeavingUnnamedTakesTheMarker() throws {
        let app = openSeededCalendar()
        let day = try firstEmptyDay(in: app, from: [20, 21, 22, 23, 24])

        let before = KeyboardAvoidanceTestSupport.dayCell(day: day, in: app)
        XCTAssertFalse(
            before.label.lowercased().contains("event"),
            "Day \(day) must start empty or this test proves nothing; label = \(before.label)"
        )

        KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)

        // The editor is what the report is about, so assert we actually got there.
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 5),
            "Tapping an empty day should open the batch editor"
        )

        // The point of the report. The editor stages an event on the tapped day, and the
        // editor's own calendar is where the user sees that.
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
            """
            The tapped day should be marked in the batch editor's calendar — a draft is \
            staged on it. Day \(day) is unmarked; label = \
            \(KeyboardAvoidanceTestSupport.dayCell(day: day, in: app).label)
            """
        )

        // Leaving without naming it. Nothing was written, so the mark is the editor's own
        // projection of a staged assembly and goes with it.
        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)

        // Wait for the editor to actually leave before reading the day. `dayCell` returns the
        // *topmost hittable* cell, and during the pop transition the editor's calendar is
        // still hittable and still marked — so asserting immediately reads the screen being
        // dismissed and reports a failure that is really a race. Same reason the
        // editor-present assertion above waits for `batch-editor-back-button` first.
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForNonExistence(timeout: 5),
            "The batch editor should be dismissed after going back"
        )

        XCTAssertFalse(
            KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
            """
            An untouched draft was never written, so day \(day) must go back to unmarked; \
            label = \(KeyboardAvoidanceTestSupport.dayCell(day: day, in: app).label)
            """
        )
    }

    /// The other half of the guarantee: naming it *does* persist, and the mark is real. Without
    /// this, "the marker disappears" would pass for an implementation that simply never marks
    /// anything.
    @MainActor
    func testNamingTheBatchKeepsTheDayMarked() throws {
        let app = openSeededCalendar()
        let day = try firstEmptyDay(in: app, from: [20, 21, 22, 23, 24])

        KeyboardAvoidanceTestSupport.tapDay(day: day, in: app)
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 5),
            "Tapping an empty day should open the batch editor"
        )

        let nameField = app.textFields["batch-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "The batch editor should offer a name field")
        // Asserted on `placeholderValue`, never on `value`. XCUITest reports an empty
        // TextField's *placeholder* as its value, so an empty field with a placeholder and a
        // field pre-filled with that same string are indistinguishable through `value` — and
        // this test exists precisely to tell those two apart.
        XCTAssertEqual(
            nameField.placeholderValue, "New event",
            "the default is offered, not committed"
        )
        KeyboardAvoidanceTestSupport.replaceText(in: nameField, with: "Cycle")

        KeyboardAvoidanceTestSupport.leaveCurrentScreen(in: app)
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForNonExistence(timeout: 5),
            "The batch editor should be dismissed after going back"
        )

        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
            """
            Naming it wrote the batch, so day \(day) stays marked; label = \
            \(KeyboardAvoidanceTestSupport.dayCell(day: day, in: app).label)
            """
        )
    }
}
