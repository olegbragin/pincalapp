# Test Baseline

Recorded on `feature/batch-editor/stage-0` at commit `0492392`
("overall reafactor"), before any refactoring work.

**Purpose:** every stage of `REFACTOR_PLAN.md` must end with the same suite, at the
same or a higher pass count, with no new failures. This file is the reference. If a
stage ends below these numbers, that stage is not done.

## Recorded run

| Target | Tests | Result | Duration | xcresult |
|---|---:|---|---:|---|
| `PinCalAppTests` | 0 | stub only, contains no tests | — | — |
| `SingleCalendarFeatureTests` | 132 | 132 passed, 0 failed, 0 skipped | 34.9 s | `test_sim_2026-09-27T22-04-40-576Z_pid46217_8c371823.xcresult` |
| `AppNavigationTests` | 21 | passed | (batched) | `test_sim_2026-09-27T22-05-19-870Z_pid46217_2d8f3b21.xcresult` |
| `CoreDomainTests` | 16 | passed | (batched) | ″ |
| `CorePersistenceTests` | 16 | passed | (batched) | ″ |
| `DSKitTests` | 17 | passed | (batched) | ″ |
| `CalendarListFeatureTests` | 18 | passed | (batched) | ″ |
| `SettingsFeatureTests` | 9 | passed | (batched) | ″ |
| **Unit subtotal** | **229** | **229 passed, 0 failed** | **90.6 s** | |
| `PinCalAppUITests/BatchEditCommitTests` | 7 | 7 passed | 268.3 s | `test_sim_2026-09-27T22-06-39-329Z_pid46217_80cf89c9.xcresult` |
| `PinCalAppUITests` — `PinCalAppUITests`, `PinCalAppUITestsLaunchTests`, `KeyboardAvoidanceTests`, `KeyboardAvoidanceLandscapeTests`, `EditorKeyboardAvoidanceTests`, `PerfScrollTests` | 22 | 22 passed | 578.5 s | `test_sim_2026-09-27T22-11-11-977Z_pid46217_27d6755a.xcresult` |
| **UI subtotal** | **29** | **29 passed, 0 failed** | **846.8 s** | |
| **Total** | **258** | **258 passed, 0 failed, 0 skipped** | **~15.7 min** | |

Device: iPhone 18 Pro, iOS Simulator, `1C68A5B2-9FD2-485D-A95D-5B14BED87F2D`.
Build: `build_run_sim` clean, 21.2 s.

## Current state — after Stage 13 (§17)

The table above is the Stage 0 reference and stays as recorded; it is the oracle the
deltas in §"Expected deltas" are measured against. This is where the suite actually
stands.

| Target | Tests | Result |
|---|---:|---|
| `PinCalAppTests` | 31 | 31 passed — gained `CalendarStoreTests` + `RootMapperTests` in Stage 3; was a 0-test stub |
| `SingleCalendarFeatureTests` | 183 | 183 passed |
| `CalendarListFeatureTests` | 20 | 20 passed |
| `CoreDomainTests` | 34 | 34 passed |
| `CorePersistenceTests` | 16 | 16 passed |
| `DSKitTests` | 25 | 25 passed |
| `SettingsFeatureTests` | 9 | 9 passed |
| **Workspace subtotal** | **318** | **318 passed, 0 failed** |
| `AppNavigationTests` | 25 | 25 passed — **separate SwiftPM package, not in the workspace gate.** Run `cd Packages/AppNavigation && swift test` or it is silently missed |
| **Unit total** | **343** | **343 passed, 0 failed** |
| `PinCalAppUITests` (all 13 classes) | 44 | **44 passed** — see the note below before quoting this |
| **Total** | **387** | **387 passed, 0 failed** |

> **How the 381 was reached, precisely — and the caveat that was here a moment ago.**
> The *first* full-plan run through `AutoTestRunner` (iPhone 17 Pro - AutoTest, §17.1)
> reported **381 completed, 2 failures**. Both were the §17.5 pre-fill bug reached through
> the shared `createBatch` helper. Both were fixed, each re-run green, and the full plan was
> then re-run end to end: **381 completed, 0 failures, 0 skipped**, reset on attempt 1.
> That last line is the real result. The two earlier lines are kept because "the suite went
> red for a reason and here it is" is more useful to the next reader than a clean number
> with no scar.

### The AutoTest simulators — the project's intended UI surface

Run via `Packages/AutoTestRunner` (`--profile iphone|ipad`), which erases both
`-AutoTest` simulators before every run so no state carries over. **Both simulators after
a full reset:**

| Device | Tests | Result |
|---|---:|---|
| `iPhone 17 Pro - AutoTest` (EF5B70CF) | 381 | **381 passed, 0 failures, 0 skipped** — full plan, reset on attempt 1 |
| `iPad Pro 13-inch (M5) (16GB) - AutoTest` (19044F68) | 381 | **379 passed, 2 failures** — the two long-standing iPad failures below, unchanged |

**Both rows are full-plan runs of 381 tests through `AutoTestRunner` itself** — not
hand-assembled xcodebuild invocations. Superseded by the Stage 14 work below; kept as the
Stage 13 record.

| Device | Result |
|---|---|
| `iPhone 17 Pro - AutoTest` | **381 passed, 0 failures, 0 skipped** |
| `iPad Pro 13-inch (M5) (16GB) - AutoTest` | 379 passed, 2 failures — both pre-existing iPad layout tests |

## Stage 14 — the two iPad failures

Both were iPad-only. The iPad split view differs from a phone in three ways the suite
assumed away: the sidebar starts **collapsed** (its rows are absent from the hierarchy, and
the bar's only control is a "Show Sidebar" button); there is no Back button in the detail
column, so leaving has to be expressed through the sidebar; and a narrower detail column
**collapses the toolbar into an overflow menu**. Also relevant: `goTo(.sidebar)` only clears
`detailCalendarID` for `.archived` and `.settings`, so tapping the category the app is
already on is a no-op and leaves the same calendar alive.

| Test | iPad before | iPad after |
|---|---|---|
| `CalendarListRefreshTests` (3 tests) | 2 pass, 1 fail | **3 pass** |
| `PinCalAppUITests.testLeavingCalendarInMultiselectModeResetsOnReopen` | fail | **still fails — now an app bug, not a test bug** |

`openArchivedList` tapped `BackButton` unconditionally; on iPad that is the *sidebar's*
control, so it collapsed the sidebar and then failed to find the row it had just navigated
to. It now navigates only when the sidebar is not already reachable.

### The remaining failure is diagnosed, and it is not the harness

`testLeavingCalendarInMultiselectModeResetsOnReopen` used to fail on
*"After reopening, the calendar should be in single-select mode"*, which read as a
selection-state bug. It is not. Chasing it produced two **real harness defects** first, both
fixed:

- Every toolbar assertion now goes through `toolbarAction` / `toolbarActionExists` /
  `waitForToolbarAction` / `tapToolbarAction`, which open the `plus` overflow menu when an
  action is not on the bar. A present, tappable action was being reported as missing purely
  because the toolbar had collapsed.
- `openCalendarDetail` asserted only that the calendar row *existed*, then tapped and
  returned. It now waits for a day cell — the grid is the sentinel for "we are on the
  calendar" — and re-taps up to three times, failing with an explicit message otherwise.

With those fixed, the true cause is visible: **on iPad, once the sidebar is revealed, tapping
a calendar card does not set `detailCalendarID`, so the detail column never opens.** The list
and its empty-detail placeholder ("Select a calendar / Choose a calendar from the list") stay
on screen, and three taps of a hittable row change nothing. Leaving the calendar on iPad
requires the sidebar, and coming back is what does not work — so a user who opens the sidebar
and then picks a calendar gets no calendar. **This needs an app fix, not a test fix.**

Verified on iPhone after all of the above: **40/40 UI tests green**, no regression from the
shared-helper changes.

## Stage 15 — tooling and framework boundaries

**`AutoTestRunner` now runs `mobilebuildmcp`, not `xcodebuildmcp`.** The tool was renamed and
*both* binaries are on `PATH` — the old name still resolves, to the previous release
(`mobilebuildmcp` 2.7.1, `xcodebuildmcp` 2.7.0) — so the runner was working while running a
version behind. The config directory it reads is `.mobilebuildmcp/config.yaml`, which was
already correct.

### XCTest versus Swift Testing: where the line actually is

The request was "no XCTest at all". The repository is already there for everything that can
be, and the remainder cannot be:

| Area | Files | Framework |
|---|---:|---|
| Unit tests (7 targets) | 29 | **Swift Testing** — `@Suite` / `@Test` / `#expect` |
| UI tests (`PinCalAppUITests`) | 11 | XCTest — and required to be |

`import XCTest` appears in exactly the 11 files of the UI-test target and nowhere else in the
repository; there is no `XCTestCase` outside `PinCalAppUITests`. So there is no unit-test
migration to do — it is already done.

The 37 UI tests cannot move to Swift Testing. XCUITest is built on XCTest and runs in an XCTest
UI-test runner; `XCUIApplication` and `XCUIElement` have no `Testing`-framework equivalent and
swift-testing provides no bridge to the runner. Rewriting them would mean deleting the UI suite,
not converting it. Their 230 `XCTAssert` calls and 169 `waitForExistence` queries are the
vocabulary of that framework, not a leftover to clean up.

**The boundary to preserve:** `import Testing` for anything that calls your own code;
XCTest only where `XCUIApplication` is involved. A future change that introduces
`XCTestCase` into a package target is a regression against that.


## Stage 16 — a tapped empty day, marked and un-marked

**STR:** open a calendar, tap a day with no events on it.

**AB:** the batch editor opens with the tapped day **unmarked**; pressing back then leaves a
marker on that day, so it looks like it holds an event that was never written — marked in
memory, not persisted.

**EB:** the tapped day is marked in the editor's own calendar, and back takes the marker with
the discarded edit.

### Two faults, plus a third that made both invisible

Neither half was where the report pointed.

1. **The payload was never recomputed when the assembly was staged.** `dayTappedInCalendar`
   built a new assembly and requested the push, but never rebuilt `dayEventColors`, so the
   editor's calendar had nothing to paint. This is the same omission that had already cost
   the multi-select marker once (§17.2).
2. **The system Back button never told the store anything.** The batch editor relied on the
   `NavigationStack`'s own back control, which pops the path directly. `backTapped` — the
   action that discards the staged edit — was simply never dispatched, so the assembly
   outlived the screen that was editing it. That is the actual source of the phantom marker,
   and it is why the "unmarked in the editor" half *looked* like the whole bug: the store
   was still holding the assembly, so back had nothing to clean up.
3. **`dayEventColors` was maintained by hand at fourteen call sites.** Each site was
   individually reasonable and each omission was invisible in review. It is now derived once
   at the reducer's single exit, via `PCEventSelectionState.derivedDayEventColors`.

Making it structural surfaced the rejected-action contract immediately: nine tests asserting
"a refused action leaves the state byte-identical" began failing, because their *fixtures*
hand-wrote a payload that disagreed with what the state implied — states the reducer could
never have emitted. The derivation is now shared with the fixtures, so an inconsistent
hand-built state is not expressible.

The same hole as (2) exists on the day-list and event-editor screens, which also rely on the
system back. Only the batch editor is fixed; the other two are listed as remaining work.

**Verified:** iPhone 41/41 UI, 343 unit across 8 targets. The new UI test
(`EmptyDayTapMarkerTests`) was confirmed failing on the AB behaviour before the fix, and
passing after; the reducer contract is also covered by two unit tests, which is where the
"marker must not outlive the edit" half actually belongs.


## Stage 17 — the other two pushed screens own their Back button

The system Back control on the day list and the event editor popped the `NavigationStack`
without telling the store, exactly as the batch editor's did. Both now render their own Back
and dispatch `backTapped`; `PCToolbarPlacement.pcLeading` was added alongside `pcTrailing` for
the leading slot.

`toggleDay` is the **only** action in the whole reducer gated on `stage == .batchEditor`, and
that is what decides how bad each screen's copy of the bug is:

| Screen | Stale stage is… | Visible failure | Test |
|---|---|---|---|
| Event editor | `.eventEditor` | **The batch editor goes inert.** Tapping days to add them to the batch does nothing — no error, no disabled control, nothing in the log | confirmed failing before the fix |
| Day list | `.dayList` | **Latent.** No action is gated on it, so nothing the user can do is refused | confirmed *passing* before the fix |

The day-list row above is the interesting one: the test was written, the fix reverted, and the
test **passed anyway** — which is the honest result and is why the test guards the navigation
rather than claiming a failure mode that does not exist. A test that passes against the broken
behaviour is worse than no test, because it looks like coverage.

### The iPad sidebar bug is four tests, not one

Correcting §14. `BatchEditCommitTests` was never run on the iPad, so three of its tests were
never measured. All three fail there for the same single root cause, and the trace is
identical in each: `Show Sidebar` → `sidebar-settings` → the day cell never comes back.

| Test | iPad |
|---|---|
| `testLeavingCalendarInMultiselectModeResetsOnReopen` | fails |
| `BatchEditCommitTests.testChangingEventColorPersistsAfterBatchSave` | fails |
| `BatchEditCommitTests.testEditingExistingEventShowsPreFilledNameAndPersistsChanges` | fails |
| `BatchEditCommitTests.testSavingBatchFromEditorUpdatesCalendarWithoutReachingRoot` | fails |

### Three harness faults found, and where the investigation actually landed

Each was measured, not reasoned about, and two of them are the same shape as the
`navigationBars.firstMatch` problem from §14 — a bare subscript is a `firstMatch` query, and
on a split view the first match is frequently not the control meant.

1. **`app.buttons["Hide Sidebar"]` resolved to the wrong button.** With the sidebar revealed
   there are **two** such controls in the hierarchy, and the first reported
   `isHittable == false` while the second reported `true`. The helper was reporting the
   sidebar un-collapsible with a tappable button sitting right there. It now searches all
   matches. Measured: Hide count 2 → 0 afterwards, and `Show Sidebar` returns.
2. **The leave sequence was in the wrong order.** It went Settings → collapse, which strands
   the app on the *Settings* screen with the sidebar rows gone, so nothing can switch back to
   Calendars. Measured: after that sequence the calendar list was entirely absent
   (`sidebar-calendars` unreachable, no calendar row in the hierarchy) — which is how three
   tests failed on *"day cell should exist"* while looking like a navigation bug. It is now
   Settings → Calendars → collapse, which lands in exactly the state the app is in when
   launched by hand: list showing, detail cleared, sidebar collapsed.
3. **`app.staticTexts[name].firstMatch` was the sidebar row, not the calendar card.** The
   sidebar row and the card carry the same name, and the first match measured as the sidebar
   row. Tapping it switches the sidebar category and leaves the list on screen, so the test
   concluded the calendar "did not open" and blamed the app for a tap that never reached the
   card. On the iPhone there is one match, so it passes there and the difference reads as an
   iPad app bug. `openCalendarDetail` now prefers the last hittable match.

### The actual cause: the detail column is never displayed, so nothing loads

Column-level accessibility identifiers (`root-sidebar-column`, `root-content-column`,
`root-detail-column`, plus `calendar-card-<id>` on each card) settled it, because the question
"did the calendar open" cannot be answered from the elements *inside* — the list and the
calendar both render day cells and both carry the calendar's name.

What the identifiers show, tapping the card **by its own id** on the iPad:

| Observation | Meaning |
|---|---|
| `calendar-card-1` present, hittable, frame `(16, 98, 308, 200)` | the card is really on screen and really tappable |
| detail column's `emptyState` goes `true` → `false` | `onSelectCalendar` **ran**, and `detailCalendarID` **was** set |
| `calendar-detail-1` stays absent, 2 spinners persist | `CalendarDetailView` is built but never renders its content |

`CalendarDetailView` creates its model inside `.task(id:)`, and **`.task` does not run until the
view appears**. The detail column is therefore being *built* while never being *displayed*:
with the sidebar collapsed, `NavigationSplitView` presents two of its three columns, and the
detail has nowhere to go. So `onSelectCalendar` runs, the card draws its selection ring, the
placeholder disappears — and no calendar ever appears. The user sees a highlighted card and no
calendar, which is precisely the reported symptom.

**This is an app bug, not a test bug.** `RootView` pins
`preferredCompactColumn` to `.sidebar` for every non-compact size class, which is what starves
the detail column on the iPad. The fix is column *visibility* rather than column *preference* —
`NavigationSplitView(columnVisibility:)` driven by whether a calendar is selected, with
`preferredCompactColumn` left to mean what it says (compact width only). That is a root-layout
change affecting how the iPad presents the app, so it is a decision rather than a patch, and it
is not made here.

Two changes made on my earlier, wrong reasoning were reverted rather than left behind: a
`Button` replacing the card's `.onTapGesture` (the tap was never the problem) and preferring the
*last* hittable calendar-name match (`firstMatch` did reach the card). The column and card
identifiers are kept — they are what made the diagnosis possible, and every layout assertion in
the suite can now be asked directly instead of inferred.

Two harness faults from the same investigation are genuine and kept, both measured: the
`Hide Sidebar` `firstMatch` problem (two controls, first not hittable) and the leave ordering
(Settings → Calendars → collapse, or the app is stranded on Settings with no way back).

**Verified:** iPhone 43/43 UI, 343 unit across 8 targets. No iPhone regression from any of the
three harness fixes.


## Stage 18 — the accessibility instrumentation was a trap (reverted)

Adding per-column and per-card accessibility identifiers, to answer "which column is on
screen" directly instead of inferring it, **broke 30 tests across three classes**. The full-plan
run through `AutoTestRunner` reported 386 completed, **30 failures**, with
*"Calendar should load"*, *"day cell should exist"* and *"detail view should appear"* — the
calendar list could no longer be read by name at all.

Two things did it, and both are worth more than the diagnosis they enabled:

- `.accessibilityElement(children: .contain)` on a card **rewrites that subtree's accessibility
  tree**, and the card's name stopped being exposed as a `StaticText`. A calendar list is read
  by name; take the names away and the list cannot be opened.
- `.accessibilityIdentifier` on a **column root** was enough to break the iPhone on its own.
  The failures are indistinguishable from "the app is broken", which is what made this
  expensive: the build succeeded, the app ran, and 30 tests said otherwise.

An identifier is *additive*; an `accessibilityElement` is a *rewrite*. Every change here has
been reverted — `RootView`, `RootContentView`, `RootDetailView`, `RooSidebarView` and
`CalendarListContent` are all back to their committed state.

The identifiers did earn their keep before they were removed: they are what turned "the iPad
calendar does not open" into "the tap runs, the placeholder disappears, and the detail never
loads". That diagnosis stands, and the next step for it is a view debugger, not more
instrumentation in shipping code.

### The iPad fix was attempted and did not work

Replacing the forced `preferredCompactColumn = .sidebar` with
`NavigationSplitView(columnVisibility:)` was the obvious move. It was measured, not assumed:
**`.doubleColumn` and `.all` both produced byte-identical frames** to the forced sidebar — the
content column stayed 308pt wide and the detail still did not appear. So `columnVisibility` is
not what decides the iPad's column width here, and the edit was reverted rather than left in as
an unverified root-layout change.

**The iPad detail-column bug is still open.** What is known: the card tap runs
(`onSelectCalendar` fires, the empty state goes away, the card draws its selection ring) and
`CalendarDetailView` is constructed but never loads, because it creates its model in `.task(id:)`
and `.task` does not run until the view appears. What is not known: why the column is not
appearing. That needs a view debugger session or a dump of the running scene, not another probe.

**Verified:** iPhone 17 Pro - AutoTest, full plan through `AutoTestRunner` on a freshly erased
simulator — **386 completed, 0 failures, 0 skipped**, reset on attempt 1.


## Stage 19 — Undo on the archive toast

**STR:** open the calendar list, archive a calendar, press Undo on the toast.
**AB:** the restored calendar does not come back to the active list. **EB:** it does.

### The bug was a copy-paste, and it hid in the list that *looked* right

`CalendarCache.restoreCalendar` was a verbatim copy of `archiveCalendar`: evict from the
in-memory cache, `broadcast(.delete(item:))`. A delete is a true statement about a
permanently deleted calendar and a false one about a restored one. So the restore published a
*removal*, the cache had already dropped the calendar, and nothing ever added it back.

It survived because the **archived** list looked correct — the card did vanish from it, which
is what you want to see — while the failure showed up in the *active* list, which had nothing
to add. The report and the defect were in different screens.

`undoArchive` had a comment asserting this could not happen: *"The restore publishes a change
that `applyChange` folds in… An extra `loadActive()` would only discard its own result."* The
premise was never true, and the comment is what stopped anyone looking. `updateCalendar`
already had the right shape — refetch, replace in cache, `broadcast(.change(item:))` — so the
fix is that shape, and the refetch matters: the DTO handed in still carries
`isArchived == true`, and publishing that would tell the active list to filter the calendar
straight back out.

### Test affordances

- **The toast names itself** (`archive-undo-toast`) and its action is a real `Button`
  (`archive-undo-toast-button`). The action used to be a `Text` inside a tap gesture on the
  whole toast, so "press Undo" was not expressible — only "tap the toast near the right third",
  which passes by luck and fails by geography.
- **`.accessibilityElement(children: .contain)` on the toast**, and only on the toast. Without
  it SwiftUI merges the toast's children and the button's identifier matches nothing. It is
  explicitly *not* safe on a list card: applied there in §18 it rewrote the subtree and the
  card's name stopped being exposed as a `StaticText`, breaking 30 tests.
- **The undo window is injected** (`-UITestUndoWindowSeconds`, following `-UITestColumns`).
  A toast lives ~5 seconds; asking a test to find one inside that is a coin flip on a loaded
  simulator, and a flaky test is worse than none because it looks like coverage. Production
  still uses 5s.

**Verified:** the test fails on the restore without the cache fix and passes with it, and the
full plan through `AutoTestRunner` is **387 completed, 0 failures, 0 skipped**.
