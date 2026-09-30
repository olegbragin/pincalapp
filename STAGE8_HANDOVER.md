# Stage 8 Handover — batch-assembly cutover

**Status: Stages 8 through 13 complete. §16 and §17 fixed. Unit green (341). iPhone full
plan green: 381/381, 0 failures, 0 skipped, through `AutoTestRunner` on a freshly erased
simulator.**

**One iPad test is still red, and it is an app bug rather than a test bug.**
`testLeavingCalendarInMultiselectModeResetsOnReopen` used to report a multi-select state
failure. Chasing it fixed two real harness defects — toolbar assertions are now
overflow-menu-aware, and `openCalendarDetail` now verifies the detail actually opened instead
of only that the row existed — and then exposed the real thing: **on iPad, once the sidebar is
revealed, tapping a calendar card does not set `detailCalendarID`, so the detail column never
opens.** Leaving the calendar on iPad requires the sidebar, and returning does not work, so a
user who opens the sidebar and picks a calendar gets no calendar. `TEST_BASELINE.md` §14 has
the full account. iPhone is unaffected: 40/40 UI tests green.

**XCTest is confined to the UI-test target and is meant to stay there.** Every unit test
already uses Swift Testing; `import XCTest` appears only in the 11 `PinCalAppUITests` files,
and it must — XCUITest runs in an XCTest runner and swift-testing has no bridge to it.

Nothing is committed; all six stages are on disk.

Read `REFACTOR_PLAN.md` for the design. This file is about where the cutover got to, what
it had to fix on the way, and what is still owed.

---

## 1. Gates as they stand

| Gate | Result |
|---|---|
| Production build (`PinCalApp`) | ✅ |
| Unit, 7 workspace targets, serial | ✅ **314 / 314** |
| `AppNavigationTests` (`swift test`, separate package) | ✅ **25 / 25** |
| `PinCalAppUITests` (full suite) | ✅ **37 / 37, 0 failures, 917 s** |

**Always pass `-parallel-testing-enabled NO`.** With parallel testing on, cross-suite
main-actor contention produced a hard `Index out of range` crash that poisoned 136 tests
including previously-green ones. This is a harness artefact, not a logic bug — do not
chase it.

**Unit is run in two places.** `AppNavigationTests` is a separate SwiftPM package and is
**not** in the workspace's test targets, so it is missed by the usual 7-target gate. Run
`cd Packages/AppNavigation && swift test` separately. It was never in the gate for
Stages 5b–7.

**`SingleCalendarFeature` cannot be run with `swift test`.** It is iOS-only and
`AddEditEventBatchScreen` uses `pcDisableInteractivePopGesture`. Every package target has
to go through the workspace.

---

## 2. What landed

Production: **net −733 lines.**

**Routes** (`Packages/AppNavigation`)
- `dayBatches` / `batchEditor` / `eventEditor` lost their payloads; `BatchEditorSource`
  and `EventEditorSource` deleted. A route now says *where*; the destination reads *what*
  from the store.
- `RootNavigation.pop()` added — the store emits `.pop` and nothing could express it.

**Deleted**
- `PCEventsSelectionManager.swift` (399 lines) — the old batch manager.
- `RenamedTypeShims.swift` — the `AddEditListView` typealiases.

**`PCEventSelectionNavigator`** (new) — the single place a `NavigationRequest` becomes
navigation, so view models stay free of `AppNavigation`.

**`PCEventSelectionManager`** gained `installDayTapHandler` / `clearDayTapHandler`.

**`SingleCalendarModel`** rebuilt on the store (407 → ~154 lines). Keeps only what the
store deliberately does not: the **main** panel's year matrix and its own
`daySelectionManager`. It no longer imports `CorePersistence` — Stage 9 moved its calendar
metadata to `CalendarPersisting.calendar(id:)` and `CalendarManaging.changes()`, and
`Package.swift` no longer lists the dependency for this target.

**All four view models** are now `struct` projection facades over the store, no stored
domain state, two-way controls via `Binding(get:set:)`. `AddEditEventBatchListViewModel`
keeps only `pendingDeletion`.

**All six views + two layouts** re-signed; screens take `(calendarID:)` or nothing;
`onDayTapped` replaces the `selectedDays` observer.

**Test scaffolding:** `TestSupport.swift` adds `InMemoryCalendarPersisting` (domain-native
`CalendarPersisting` fake, assigns ids on write) and `Fixture`. `InMemoryCalendarRepository`
moved there from `SingleCalendarModelTests`.

---

## 3. The five defects the UI suite found, and 356 green unit tests did not

This is the argument for having banked the pre-cutover reference (§12.3a) rather than
cutting over blind. Each of the first four is a product defect; the fifth is a class of
test defect they collectively exposed.

### 3.1 `SingleCalendarView` never fulfilled `navigationRequest`

A day tap staged a batch and requested a push; nothing carried it out. **All 19**
batch-flow UI tests failed while the unit suite was green. Adding the
`.onChange(of: store.state.navigationRequest)` handler took `BatchEditCommitTests` from
0/7 to 5/7.

### 3.2 The marker projection unioned the staged batch with its committed row

`PCCalendarMarkerProjector.colorsByDay(from:includingStaged:)` appended the two lists.
Staging is not always *creating*: an assembly opened with `existing(_:)` **is** that row,
still carrying its `persistedID`. So the projection unioned a row with itself:

- an event deleted from the staged copy kept painting its marker, because the committed
  copy still listed it — removing a day's last event left it marked permanently;
- a day both copies held was counted **twice**, so a batch with one event on a day was
  labelled with two.

This is what the "empty name, grey colour, one event" observation in the old §4 was
actually seeing. The staged row now *replaces* the committed row sharing its `mergeKey`.

**The lesson, since it cost the most time:** the two hypotheses that were chased first —
"the main calendar isn't re-projecting markers" and "two mounted screens both fulfil the
pop" — were both *downstream* of the real cause, and both were unfalsifiable from the
outside because the projection was faithful. **The payload was wrong, not the projection.**
A projection bug looks exactly like a re-projection bug until you check what the
projection was asked to draw.

### 3.3 `openBatch` looked a row up by a non-durable `pendingID`

`CalendarEventBatch.init` mints a fresh `pendingID` per row per load, because a DTO
carries none, and `SingleCalendarModel` re-syncs on **every** calendar write. So any write
invalidated the `pendingID` of the row a card on screen was drawn from. The card's closure
held the value from the last render, the lookup missed, the action was rejected, and the
tap did nothing — silently.

`openBatch` now carries the row's `mergeKey`, which needs a new
`BatchAssembler.mergeKey` that folds in `adoptedPersistedID` (a just-saved new batch has
only adopted its id and is otherwise still on its `.pending` key). `openEvent` and
`removeEvent` still use `pendingID` and that is correct: their targets live inside the
staged assembly, which is never rebuilt from a DTO.

### 3.4 `canSave` required a non-empty batch, which made the delete unreachable

`BatchAssembler.canSave` shipped with `!batch.events.isEmpty` added. The editor's Save is
`.disabled(!canSave)`, so `saveTapped`'s branch for a batch that "saves but resolves to
nothing" — the delete — became **unreachable**. A user who removed every event could not
commit the removal, and the only way out left was Back, which *discards* the edit.

The plan (§5.4.2) had it right: a name and a colour, never the event list. `resolved()`
still returns `nil` for an empty batch, so `commitTapped`'s `let row =` guard — not this
flag — is what stops an eventless row from being written.

### 3.5 Six UI tests that never picked a colour

A batch staged by tapping an empty calendar day has `colorName: ""`, so the editor's Save
is disabled and the tap is a no-op. Six tests were affected, and they failed in two
different ways:

- four failed outright with "Batch editor should dismiss after Save";
- **two were passing *because* the tap did nothing.** `createBatch` saved an unmodified
  batch, so `testDeletingAllEventsFromBatchEditorListDeletesBatch` and
  `testBatchListStillShowsBatchAfterRemovingAnchorDay` asserted against a batch nobody
  had edited. The second's expectation was also wrong on its own terms — it wanted the
  batch in **day 11's** list after removing day 11's event, but `dayBatches` filters on
  `occurs(on:)`, so the batch correctly moves to day 12.

**A test that passes against a disabled button is worse than no test**: it reports
coverage of an edit that never happened. `KeyboardAvoidanceTestSupport.selectColor(_:in:)`
now exists, and `createBatch` asserts `isEnabled` so this fails at the cause.

### 3.6 The reducer fix that was there all along

`cancelMultiSelectTapped` cleared the days and colour but left `multiSelectMode` on, so the
picker survived a cancel. The old `cancelMultipleChanges()` toggled the mode. §6.3's row
is silent about this and is now corrected.

---

## 4. Ruled out — do not re-try

- ❌ *"Store identity diverges."* `PinCalAppApp` builds one `PCEventSelectionManager` and
  hands it to both the session and the environment; `CalendarDetailView` reads it from
  the session. One instance, always.
- ❌ *"The main calendar isn't re-projecting markers."* The `.onChange(of:
  store.state.dayEventColors) { projectMarkers() }` on `SingleCalendarView` is **correct
  and load-bearing** — the editor screens dispatch to the store directly and never go
  through `SingleCalendarModel.send`. Keep it. But adding it changed nothing, because the
  payload was wrong (§3.2), not the projection.
- ❌ *"Two mounted screens both fulfil the pop."* The stand-down guard in
  `PCEventSelectionNavigator.fulfil` is **correct and load-bearing** — three screens carry
  the handler and all three see the same `onChange` capture. Keep it. It was also not the
  cause.
- ❌ *"It's a logic bug in the parallel-testing race."* It is the harness (§1).

Both of those edits were previously recorded as "reasoned-not-proven". They are now
exercised by the full suite and are no longer speculative.

---

## 5. Not taken: seeding the assembler at the card tap

Assessed, and still the weaker half.

*What it would buy.* The store is seeded by `CalendarDetailView.task(id:)` →
`SingleCalendarModel.fetch` → `syncCalendar`. The model is constructed and rendered
*before* the async fetch completes, so there is a window where the calendar is on screen
and the store is empty. Seeding at the card tap closes it and makes "entering a calendar"
the single start of a session — which is what the UDF's `resetSession`/`syncCalendar`
already implies.

*What it would not have fixed.* §3.3. Every `syncCalendar` re-minted every row's identity
and the model re-synced on every write; seeding earlier moves the first re-mint earlier,
it does not stop them. The `mergeKey` fix came first, as planned.

*Layering constraint.* The card tap lives in `CalendarListFeature`, which should not know
about the batch-assembly store. The clean route is the one already in place: the tap does
`navigation.goTo(.calendar(id, toRoot: true))`, and the app root or `CalendarDetailView`
seeds the store in response. Worth deciding deliberately rather than wiring the store
into the list.

---

## 6. Commands

```bash
# Unit, 7 workspace targets — note the serial flag
xcodebuild test -workspace PinCalApp.xcworkspace -scheme PinCalApp \
  -destination 'platform=iOS Simulator,id=1C68A5B2-9FD2-485D-A95D-5B14BED87F2D' \
  -only-testing:PinCalAppTests -only-testing:CoreDomainTests \
  -only-testing:CorePersistenceTests -only-testing:CalendarListFeatureTests \
  -only-testing:DSKitTests -only-testing:SettingsFeatureTests \
  -only-testing:SingleCalendarFeatureTests -parallel-testing-enabled NO

# The separate package the workspace gate misses
cd Packages/AppNavigation && swift test

# Full UI suite — ~14 min, so background it and poll the log
xcodebuild test -workspace PinCalApp.xcworkspace -scheme PinCalApp \
  -destination 'platform=iOS Simulator,id=1C68A5B2-9FD2-485D-A95D-5B14BED87F2D' \
  -only-testing:PinCalAppUITests -parallel-testing-enabled NO
```

The UI runs take 3–14 min and an MCP `test_sim` call times out first — background them and
poll the log. `record_sim_video` via MCP is broken (AXe path parse); `xcrun simctl io …`
recordVideo works. MCP debugger breakpoints do not fire in this project — use `print` +
the runtime log under
`~/Library/Developer/MobileBuildMCP/workspaces/PinCal-*/logs/`. App `print` output does
**not** reach the `xcodebuild` log; use the MCP runtime log or assert on the UI instead.

Revert generated churn after every test run:
`git checkout -- Packages/SingleCalendarFeature/Sources/SingleCalendarFeature/LocalizedStringKeyExtension.swift`

---

## 7. Still owed

- **Nothing from this handover's original §4.** Both open failures are fixed; their causes
  were §3.2 (unmarked day) and §3.5 (disabled Save), not the `openBatch` identity it
  proposed.
- Stage 10 and 11 are done. Stage 10's three named leftovers were already gone with
  Stage 8 — see `REFACTOR_PLAN.md` §10.1. Stage 11 added the multi-day scenario and
  mutation-verified it; writing it turned up a real accessibility defect, recorded in §11.3.
- ~~`REFACTOR_PLAN.md` §16~~ — **fixed**, see §16.5. The batch was never deleted: the save
  popped the user to the day list for a day the edit had just emptied. Five of §16.3's six
  hypotheses are retired, and the plan's instinct about `date` was right in the wrong
  direction — `date` is derived now, so it cannot drift; it was `state.day` that was stale.
- **Every stage is uncommitted.** Nothing is pushed. `git status` will show ~45 modified
  files across 12 stages of work, not a mess.
- Nothing in the plan is outstanding. The one thing worth deciding is whether to commit in
  stages or as one — the branches `feature/batch-assembly/stage-N` the plan names were never
  created past stage 1.

---

## 8. Files touched

**Deleted:** `Model/PCEventsSelectionManager.swift`, `RenamedTypeShims.swift`,
`Tests/.../ViewModels/PCEventsSelectionManagerTests.swift`, and (Stage 9) the
`CorePersistence` dependency on the `SingleCalendarFeature` target.

**New:** `Model/PCEventSelectionNavigator.swift`, `Tests/.../TestSupport.swift`
(+ `InMemoryCalendarManaging`).

**Rewritten:** the four `AddEdit*ViewModel`s, `SingleCalendarModel`, the six editor
views, both `BatchEditor*Layout`, `SingleCalendarView`, `PCCalendarSession`,
`PinCalAppApp`, `CalendarDetailView`, `RootSelection`, `RootNavigation` (+ tests).

**Test suites rewritten:** `AddEditEventViewModelTests`,
`ViewModels/AddEditEventBatchViewModelTests`, `ViewModels/AddEditEventListViewModelTests`,
`ViewModels/AddEditEventBatchListViewModelTests`, `ViewModels/EventEditorThenBatchSaveDuplicateTests`,
`SingleCalendarModelTests`, `SingleCalendarModelObjectBoxIntegrationTests` (→ "Batch flows
end to end"), `TwoSingleDayBatchesReproTests`, `EventBatchCreationTests` (trimmed).

### Why the ObjectBox suites no longer use ObjectBox

`CalendarStore` — the DTO→domain adapter — lives in the **app target**, so a package test
cannot reach it without naming `EventBatchDataSource`, which is exactly what the DTO
boundary forbids. Those suites now assert through `CalendarPersisting` ("what the port
received") instead of reading boxes. The mapping itself is covered in `PinCalAppTests`
where the adapter is reachable. The suites could not simply move: they need
`@testable import CorePersistence` for the generated `PPCalendar` entity, which a
cross-package `@testable` cannot do.
