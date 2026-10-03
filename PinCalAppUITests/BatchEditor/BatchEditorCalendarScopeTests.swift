//
//  BatchEditorCalendarScopeTests.swift
//  PinCalAppUITests
//
//  STR: open a calendar; tap an empty day; in the batch editor tap two more days in its
//  calendar; press back; tap another empty day.
//
//  AB: the batch editor shows the days selected for all four — 2nd, 3rd, 4th and 10th.
//
//  EB: it shows only the 10th. The first three belong to a batch that is not being edited.
//
//  The report read this as the assembly being reused across sessions. It was not: the
//  assembly is a brand-new one-day batch, and the editor's *event list* said so. The editor's
//  calendar above the list was painted from the whole calendar's marker payload, so every
//  batch in the registry was drawn in a panel whose only job is picking days for one batch.
//
//  Which is worse than it looks. A marked day belonging to another batch is *added* to this
//  one when tapped, not removed from it — `toggling` only knows about the assembly. So the
//  three foreign days read as days this batch held, and tapping one would have put it on two
//  batches at once.
//
//  Asserted on the *editor's* cells deliberately: `dayCell` resolves the topmost hittable
//  match, and a pushed editor carries its own calendar over the one behind it. Reading
//  `firstMatch` here would assert about the main calendar, which marks every batch and is
//  supposed to.
//

import XCTest

final class BatchEditorCalendarScopeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openSeededCalendar() -> XCUIApplication {
        let app = KeyboardAvoidanceTestSupport.launchSeededApp()
        KeyboardAvoidanceTestSupport.openCalendarDetail(app, named: "UI Test Calendar")
        return app
    }

    /// Every candidate that is genuinely empty right now, in order.
    ///
    /// Observed rather than hard-coded: the seed data moves, and a hard-coded day that is no
    /// longer empty fails on the fixture instead of on the behaviour. Four are needed — three
    /// for the batch built first, one for the batch the report is about — so a run that finds
    /// fewer says so rather than quietly testing less.
    @MainActor
    private func emptyDays(in app: XCUIApplication, from candidates: [Int]) -> [Int] {
        candidates.filter { day in
            let cell = KeyboardAvoidanceTestSupport.dayCell(day: day, in: app)
            guard cell.waitForExistence(timeout: 2) else { return false }
            return !cell.label.lowercased().contains("event")
        }
    }

    @MainActor
    private func waitForBatchEditor(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForExistence(timeout: 10),
            "Tapping an empty day should open the batch editor"
        )
    }

    /// Leaves the editor, and lands on the calendar.
    ///
    /// **One** press, and the day list is not what is underneath. Tapping an empty day
    /// pushes the editor onto a stack that was empty — no day list was ever pushed, because
    /// there was no batch on that day to list — so Back pops the editor's own entry and the
    /// calendar is what is revealed.
    ///
    /// (The store's `stage` says `.dayList` at that point, having re-anchored on the day the
    /// batch now lives. Nothing reads it there: the day list is not on the stack, and the next
    /// day tap recomputes the stage from scratch.)
    @MainActor
    private func backToCalendar(in app: XCUIApplication) {
        app.buttons["batch-editor-back-button"].tap()
        XCTAssertTrue(
            app.buttons["batch-editor-back-button"].waitForNonExistence(timeout: 5),
            "Back should close the batch editor"
        )
        XCTAssertFalse(
            app.buttons["add-batch-button"].waitForExistence(timeout: 3),
            "and the calendar is what is revealed — no day list was pushed beneath the editor"
        )
    }

    @MainActor
    func testTheEditorsCalendarShowsOnlyTheBatchBeingEdited() throws {
        let app = openSeededCalendar()

        // Well clear of the 1st and 2nd, which the seed data occupies.
        let candidates = [6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28]
        let empties = emptyDays(in: app, from: candidates)
        guard empties.count >= 4 else {
            XCTFail("Need four empty days to run this, found \(empties) among \(candidates)")
            return
        }
        let (first, second, third) = (empties[0], empties[1], empties[2])
        let later = empties[3]

        // 1–3: a batch on three days, built the way the report describes.
        KeyboardAvoidanceTestSupport.tapDay(day: first, in: app)
        waitForBatchEditor(app)
        KeyboardAvoidanceTestSupport.tapDay(day: second, in: app)
        KeyboardAvoidanceTestSupport.tapDay(day: third, in: app)

        for day in [first, second, third] {
            XCTAssertTrue(
                KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
                "Day \(day) was added to this batch, so the editor's calendar marks it"
            )
        }

        // 4: leave, and come back to the calendar.
        backToCalendar(in: app)

        // 5: another empty day, so a brand-new batch sharing nothing with the one above.
        KeyboardAvoidanceTestSupport.tapDay(day: later, in: app)
        waitForBatchEditor(app)

        // The point of the report.
        XCTAssertTrue(
            KeyboardAvoidanceTestSupport.isDayMarked(day: later, in: app),
            "The batch being edited marks its own day"
        )
        for day in [first, second, third] {
            XCTAssertFalse(
                KeyboardAvoidanceTestSupport.isDayMarked(day: day, in: app),
                """
                Day \(day) belongs to a batch this editor is not editing, so it must not be \
                marked here — and tapping it would add it to this batch rather than remove it \
                from that one. Label = \
                \(KeyboardAvoidanceTestSupport.dayCell(day: day, in: app).label)
                """
            )
        }
    }
}