//
//  KeyboardAvoidanceTestSupport.swift
//  PinCalAppUITests
//
//  Created by Oleg Bragin on 24.08.2026.
//

import XCTest

enum KeyboardAvoidanceTestSupport {

    @MainActor
    static func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedData", "-UITestColumns", "1"]
        app.launch()
        return app
    }

    @MainActor
    static func openCalendarsList(_ app: XCUIApplication) {
        let row = sidebarRow("sidebar-calendars", in: app)
        // Tolerant on purpose: the list is often already showing, and the row is not
        // instantiated at all in compact width. It used to be queried as
        // `app.buttons[...]`, which never matches a `Label` in a selection-bound `List`
        // row — so on the iPad this quietly did nothing and the tests carried on
        // assuming it had opened the list.
        if row.waitForExistence(timeout: 2), row.isHittable {
            row.tap()
        }
    }

    /// A row of the root sidebar.
    ///
    /// The rows are `Label`s in a selection-bound `List` row, which XCUITest surfaces as
    /// `StaticText`/`Image` carrying the identifier — *not* as buttons. An
    /// `app.buttons[...]` query therefore finds nothing, and because the usual call sites
    /// are wrapped in a `waitForExistence` whose result they ignore, the failure mode is a
    /// helper that quietly does nothing rather than one that reports itself broken.
    @MainActor
    static func sidebarRow(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The sidebar row for `identifier`, revealing the sidebar first if it is collapsed.
    ///
    /// On the iPad split view the sidebar starts collapsed, in which case its rows are not
    /// in the hierarchy *at all* — not merely unhittable — and the navigation bar's only
    /// control is a "Show Sidebar" button. That is why two tests could not leave the
    /// calendar on the iPad: there was no back button to tap, and the sidebar they needed
    /// next was behind a button neither of them looked for. A query is returned rather than
    /// a boolean because XCUIElement resolves lazily, so the caller can wait on it after
    /// this returns.
    @MainActor
    static func revealedSidebarRow(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let row = sidebarRow(identifier, in: app)
        guard !row.exists else { return row }

        let show = app.buttons["Show Sidebar"]
        if show.exists, show.isHittable {
            show.tap()
        }
        return row
    }

    @MainActor
    static func openCalendarDetail(_ app: XCUIApplication, named name: String) {
        openCalendarsList(app)
        let calendarRow = app.staticTexts[name].firstMatch
        XCTAssertTrue(calendarRow.waitForExistence(timeout: 5), "Calendar '\(name)' should exist in the list")

        // Verify the detail actually opened, and re-tap if it did not.
        //
        // This used to assert only that the row *existed*, then tap and return. On the iPad
        // split view with the sidebar revealed, that tap leaves the calendar **list** on
        // screen — the empty-detail placeholder, "Select a calendar" — so every caller
        // carried on against a screen that was not the one it asked for. It surfaced as a
        // failure in whatever the caller asserted next, which is how a test about
        // multi-select mode ended up reporting a mode bug that was really a missed
        // navigation.
        //
        // The sentinel is a day cell: the grid only exists on the calendar detail, so its
        // presence is what "we are on the calendar" means here.
        let grid = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "day-"))
            .firstMatch

        for attempt in 1...3 {
            // `tap()` on an element that exists but is not hittable is silently a no-op, and
            // the row is the first thing to go off-screen or under another column when the
            // detail narrows. Wait for it to be hittable rather than trusting existence.
            scrollElementIntoView(calendarRow, in: app)
            if calendarRow.isHittable {
                calendarRow.tap()
            }
            if grid.waitForExistence(timeout: 2) { return }
        }
        XCTFail("Tapped calendar '\(name)' but the calendar detail never opened")
    }

    @MainActor
    static func tapDay(day: Int, in app: XCUIApplication) {
        let identifier = dayIdentifier(day: day)
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 5), "Day cell \(identifier) should exist")

        // Several screens can expose the same day id (main calendar under a
        // pushed editor); tap the topmost hittable one.
        let deadline = Date().addingTimeInterval(5)
        var target: XCUIElement?
        while Date() < deadline, target == nil {
            target = query.allElementsBoundByIndex.reversed().first { $0.isHittable }
            if target == nil {
                Thread.sleep(forTimeInterval: 0.2)
                _ = query.firstMatch.exists
            }
        }
        let cell = target ?? query.firstMatch

        // The year grid reflows (and animates) when its column count clamps on
        // appear/size change, so a cell's reported frame can be stale at tap
        // time. A tap at a stale center then lands on an adjacent day (often
        // the same cell of the neighbouring month), which is the source of
        // flaky day taps on the iPad split view. Wait until the frame stops
        // moving before tapping.
        _ = stableFrame(of: cell, timeout: 4)

        cell.tap()
    }

    // MARK: - Toolbar actions

    /// The toolbar's overflow control, identified by `plus`.
    ///
    /// Worth naming as a trap: `plus` is both the identifier *and* the label of the button
    /// that holds the overflow, and an `Add` item sits inside it. So a query for `"Add"` can
    /// match a toolbar item or a menu entry depending on whether the menu is open, which is
    /// why actions are resolved through the helpers below rather than by direct lookup.
    ///
    /// Every helper takes the `app` it should look at. A convenience that built its own
    /// `XCUIApplication` would address a *different* process from the one under test and
    /// would quietly report every action as absent.
    ///
    /// Why any of this exists: the iPad split view collapses toolbar items into an overflow
    /// menu once the sidebar is revealed, so an action that is present and tappable is
    /// reported as missing by a plain `app.buttons[name]` query. That made a test asserting
    /// on `Multiselect` fail on the *state* of the app when the state was fine and only the
    /// toolbar's layout had changed.
    @MainActor
    static func toolbarAction(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let direct = app.buttons[name]
        if direct.exists { return direct }

        let overflow = app.buttons["plus"]
        guard overflow.exists, overflow.isHittable else { return direct }
        overflow.tap()
        return app.buttons[name]
    }

    /// Whether `name` is available as a toolbar action, opening the overflow menu to find
    /// out and closing it again afterwards.
    ///
    /// Closes the menu because this is the *query* form: a caller asserting that an action
    /// is **absent** — which is how "single-select mode has no Save" is expressed — must not
    /// be left with a menu open over the screen, or every later query reads the menu
    /// instead of the screen.
    @MainActor
    static func toolbarActionExists(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 0) -> Bool {
        let direct = app.buttons[name]
        if direct.waitForExistence(timeout: timeout) { return true }

        let overflow = app.buttons["plus"]
        guard overflow.exists, overflow.isHittable else { return false }

        overflow.tap()
        let found = app.buttons[name].waitForExistence(timeout: max(timeout, 3))
        closeToolbarOverflow(in: app)
        return found
    }

    /// Waits up to `timeout` for `name` to be available as a toolbar action.
    @MainActor
    static func waitForToolbarAction(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        toolbarActionExists(name, in: app, timeout: timeout)
    }

    /// Taps `name` as a toolbar action, opening the overflow menu if that is where it lives.
    @MainActor
    static func tapToolbarAction(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let action = toolbarAction(name, in: app)
        guard action.waitForExistence(timeout: timeout) else {
            XCTFail("Toolbar action '\(name)' is not available")
            return
        }
        action.tap()
    }

    /// Dismisses the overflow menu, leaving the screen as it was found.
    @MainActor
    static func closeToolbarOverflow(in app: XCUIApplication) {
        let overflow = app.buttons["plus"]
        guard overflow.exists, overflow.isHittable else { return }
        overflow.tap()
    }

    /// Opens the batch list for `day` and waits until that screen is actually up.
    ///
    /// The wait is the point. Tapping a day that has batches pushes a screen that has to
    /// build its rows, and a caller that taps and immediately asserts on a row is racing
    /// that screen's appearance — which is a flake that gets blamed on the feature. The
    /// "add batch" control exists only on the day list, so it is the sentinel.
    ///
    /// Returns whether the list opened, so the caller can assert on *that* rather than on a
    /// row that would be missing for the uninteresting reason.
    @MainActor
    @discardableResult
    static func openDayBatchesList(day: Int, in app: XCUIApplication) -> Bool {
        tapDay(day: day, in: app)
        return app.buttons["add-batch-button"].waitForExistence(timeout: 10)
    }

    // MARK: - Reading a day's marker state

    /// The day cell for `day`, topmost hittable one.
    ///
    /// "Topmost" because a pushed or presented editor carries its **own** calendar, so the
    /// same identifier resolves to two elements at once: the main calendar's behind and the
    /// editor's in front. `firstMatch` is whichever XCUITest happens to enumerate first, and
    /// in a batch editor that is the one behind — so an assertion about what the editor's
    /// calendar shows would be reading the screen the editor is covering.
    @MainActor
    static func dayCell(day: Int, in app: XCUIApplication) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: dayIdentifier(day: day))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let top = query.allElementsBoundByIndex.reversed().first(where: \.isHittable) {
                return top
            }
            _ = query.firstMatch.exists
            Thread.sleep(forTimeInterval: 0.2)
        }
        return query.firstMatch
    }

    /// Whether `day` currently carries an event marker.
    ///
    /// Reads the cell's accessibility label, which is `"<n>"` when the day is empty and
    /// `"<n>, <k> events"` when it is marked. That is the only channel accessibility exposes
    /// for a marker — the label carries the marker *count*, never a colour name — so a test
    /// can assert *that* a day is marked but not *which colour* it is marked in. Colour is
    /// covered by `BatchAssembler` unit tests instead, where it is a value rather than a dot
    /// on a screen.
    @MainActor
    static func isDayMarked(day: Int, in app: XCUIApplication) -> Bool {
        dayCell(day: day, in: app).label.lowercased().contains("event")
    }

    static func dayIdentifier(day: Int) -> String {        let calendar = Calendar.current
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

    /// Picks `colorName` on the colour picker the frontmost editor exposes.
    ///
    /// Any test that builds a batch from scratch needs this. Tapping an empty calendar day
    /// stages a batch with `colorName: ""`, and a batch is only saveable once it has a
    /// colour — so without a colour the editor's Save is disabled, the tap is a no-op, and
    /// the test fails on "editor should dismiss" for a reason that has nothing to do with
    /// what it is testing.
    ///
    /// Several screens can expose a `color-picker-compact` at once — the batch editor behind,
    /// the event editor in front — so this takes the topmost *hittable* one, which makes the
    /// sheet that opens belong to the screen actually being edited.
    @MainActor
    static func selectColor(_ colorName: String, in app: XCUIApplication) {
        let picker = app.buttons.matching(identifier: "color-picker-compact")
        XCTAssertTrue(picker.firstMatch.waitForExistence(timeout: 5), "Color picker should be visible")

        let deadline = Date().addingTimeInterval(5)
        var target: XCUIElement?
        while target == nil, Date() < deadline {
            target = picker.allElementsBoundByIndex.reversed().first { $0.isHittable }
            if target == nil { Thread.sleep(forTimeInterval: 0.2) }
        }
        (target ?? picker.firstMatch).tap()

        let option = app.buttons["color-option-\(colorName)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Color option \(colorName) should be visible in sheet")
        option.tap()

        // The sheet dismisses; verify the picker is back and give the binding a moment.
        XCTAssertTrue(picker.firstMatch.waitForExistence(timeout: 5), "Color sheet should dismiss")
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// Replaces a field's whole contents with `text`.
    ///
    /// **Not** `tap()` then `typeText`. A new batch arrives with "New Event" and a new event
    /// with "New Event Day" already in the field, so typing *appends*: a test that wants the
    /// name "Cycle" silently produces "New EventCycle", and then fails much later on a list
    /// lookup with a name that was never the one it typed.
    ///
    /// Triple-tap selects the line and the next keystroke replaces it. This is the same
    /// idiom the calendar-rename test already uses, and it does not depend on the delete key
    /// being reachable, which is not true on every keyboard layout.
    @MainActor
    static func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The field should be on screen before typing into it")
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        Thread.sleep(forTimeInterval: 0.2)
        field.typeText(text)
    }

    @MainActor
    static func tapBackButton(in app: XCUIApplication) {
        // iPad split-view exposes several navigation bars at once, so
        // `navigationBars.firstMatch` resolves to the wrong bar (often the
        // sidebar's "Hide Sidebar"). Prefer the explicit SwiftUI back button.
        let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button should be visible")
        back.tap()
    }

    /// Leaves the calendar detail, on either form factor, and puts the layout back the way
    /// it was found.
    ///
    /// **iPhone** — compact width does not instantiate the sidebar, so this ends up on the
    /// navigation Back button.
    ///
    /// **iPad** — the split view keeps the detail column alive, so "go back" has to be
    /// expressed through the sidebar. Three things make that non-obvious, and each of them
    /// had a test red here before:
    ///
    /// 1. The sidebar starts *collapsed*, so its rows are not in the hierarchy at all — not
    ///    unhittable, absent — and the bar's only control is a "Show Sidebar" button.
    /// 2. Selecting the category the app is *already* on is a no-op. `goTo(.sidebar)` only
    ///    clears `detailCalendarID` for `.archived` and `.settings`, so tapping "Calendars"
    ///    while a calendar is open leaves the same calendar in the detail column, still in
    ///    multi-select, still alive. The screen is never left, which is why the failure
    ///    showed up on an assertion about the *reopened* calendar rather than about
    ///    navigation.
    /// 3. Revealing the sidebar narrows the detail column, and a narrower toolbar collapses
    ///    its items into an overflow menu — after which `Multiselect` and `Save` are gone
    ///    from the bar. So a test that leaves via the sidebar and then asserts on toolbar
    ///    buttons is asserting against a layout the app never starts in.
    ///
    /// Hence the restore at the end: the sidebar goes back to collapsed, which is the state
    /// the app launches in and the state every toolbar assertion in the suite was written
    /// against. Without it, "reopen the calendar" means something different on the iPad
    /// from what it means everywhere else.
    @MainActor
    static func leaveCurrentScreen(in app: XCUIApplication) {
        let settings = revealedSidebarRow("sidebar-settings", in: app)
        if settings.waitForExistence(timeout: 2), settings.isHittable {
            settings.tap()
            collapseSidebar(in: app)
            return
        }

        let back = app.buttons["Back"].exists ? app.buttons["Back"] : app.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button should be visible")
        back.tap()
    }

    /// Collapses the iPad sidebar if this helper revealed it, so the detail column is back
    /// to the width the app launches with.
    ///
    /// Best effort, and deliberately not a failure. It used to `XCTFail` when the control
    /// would not become hittable, which is right for a *precondition* and wrong for a
    /// cosmetic restore: the toolbar assertions in the suite are overflow-menu-aware, so a
    /// narrow detail column no longer makes any of them unable to find what they are
    /// looking for. Failing a test over the width of a column would be the harness
    /// asserting something the tests no longer care about.
    ///
    /// Polled rather than checked once, because this runs immediately after a category
    /// transition and the sidebar's own control reports `isHittable == false` while that
    /// transition is still settling.
    @MainActor
    static func collapseSidebar(in app: XCUIApplication) {
        let hide = app.buttons["Hide Sidebar"]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if hide.exists, hide.isHittable {
                hide.tap()
                return
            }
            _ = hide.exists
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    @MainActor
    static func scrollElementIntoView(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while swipes < maxSwipes {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    @MainActor
    static func startEditing(cardID: Int64, in app: XCUIApplication) -> (keyboard: XCUIElement, nameField: XCUIElement, confirmButton: XCUIElement) {
        let editButton = app.buttons["card-edit-\(cardID)"]
        scrollElementIntoView(editButton, in: app)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit button of calendar \(cardID) should exist")
        if !editButton.isHittable {
            app.swipeDown()
        }
        editButton.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Keyboard should appear when editing starts")

        let nameField = app.textFields["card-name-field-\(cardID)"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Name field should appear in editing mode")
        let confirmButton = app.buttons["card-confirm-edit-\(cardID)"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3), "Confirm button should appear in editing mode")

        return (keyboard, nameField, confirmButton)
    }

    @MainActor
    static func assertAboveKeyboard(
        element: XCUIElement,
        keyboard: XCUIElement,
        tolerance: CGFloat = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let elementFrame = stableFrame(of: element)
        let keyboardFrame = stableFrame(of: keyboard)

        // In landscape mode the keyboard can be floating (minY ≈ 0).
        // When that happens the positional check is not meaningful —
        // just verify the element is still on screen and interactable.
        let keyboardAnchored = keyboardFrame.minY > 40
        if keyboardAnchored {
            XCTAssertLessThanOrEqual(
                elementFrame.maxY,
                keyboardFrame.minY + tolerance,
                "\(element.elementType.rawValue) bottom (\(elementFrame.maxY)) must stay above keyboard top (\(keyboardFrame.minY))",
                file: file,
                line: line
            )
        } else {
            XCTAssertTrue(
                element.isHittable,
                "\(element.elementType.rawValue) must remain visible and hittable when the keyboard is shown (floating)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    static func stableFrame(of element: XCUIElement, timeout: TimeInterval = 4) -> CGRect {
        var previousFrame = CGRect.null
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            guard element.exists else { break }
            let currentFrame = element.frame
            let valid = currentFrame.width > 1 && currentFrame.height > 1
            let settled = valid
                && abs(currentFrame.minX - previousFrame.minX) < 1
                && abs(currentFrame.minY - previousFrame.minY) < 1
                && abs(currentFrame.width - previousFrame.width) < 1
                && abs(currentFrame.height - previousFrame.height) < 1
            previousFrame = currentFrame
            if settled {
                return currentFrame
            }
        }
        return previousFrame.isNull ? .zero : previousFrame
    }
}
