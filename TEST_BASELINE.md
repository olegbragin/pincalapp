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
| `PinCalAppUITests` (all 11 classes) | 41 | **41 passed** — see the note below before quoting this |
| **Total** | **384** | **384 passed, 0 failed** |

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
