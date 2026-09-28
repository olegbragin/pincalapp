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

## How to re-run

Run in three batches. A single unfiltered `test_sim` exceeds the MCP request
timeout, because the UI suite alone takes ~14 minutes.

```jsonc
// 1. Unit — feature module
{ "extraArgs": ["-only-testing:SingleCalendarFeatureTests"], "progress": false }

// 2. Unit — every other module
{ "extraArgs": [
    "-only-testing:CoreDomainTests",
    "-only-testing:CorePersistenceTests",
    "-only-testing:DSKitTests",
    "-only-testing:AppNavigationTests",
    "-only-testing:CalendarListFeatureTests",
    "-only-testing:SettingsFeatureTests"
  ], "progress": false }

// 3a. UI — the batch-editor acceptance gate
{ "extraArgs": ["-only-testing:PinCalAppUITests/BatchEditCommitTests"], "progress": false }

// 3b. UI — everything else
{ "extraArgs": [
    "-only-testing:PinCalAppUITests/PinCalAppUITests",
    "-only-testing:PinCalAppUITests/PinCalAppUITestsLaunchTests",
    "-only-testing:PinCalAppUITests/KeyboardAvoidanceTests",
    "-only-testing:PinCalAppUITests/KeyboardAvoidanceLandscapeTests",
    "-only-testing:PinCalAppUITests/EditorKeyboardAvoidanceTests",
    "-only-testing:PinCalAppUITests/PerfScrollTests"
  ], "progress": false }
```

## Access contract the UI suite depends on

These identifiers are asserted by the UI tests. Every stage that touches a view must
keep them exactly as they are; changing one is a breaking change to this file.

| Identifier | Defined in | Asserted by |
|---|---|---|
| `batch-save-button` | `AddEditEventBatchView.saveButtonAccessibilityIdentifier` | `BatchEditCommitTests` |
| `batch-name-field` | `AddEditEventBatchView` name field | `BatchEditCommitTests` |
| `event-name-field` | `AddEditEventView` name field | `BatchEditCommitTests`, `EditorKeyboardAvoidanceTests` |
| `add-batch-button` | `AddEditEventBatchListView` "+" | `BatchEditCommitTests` |
| `batch-editor-calendar` | `BatchEditorVerticalLayout` / `BatchEditorHorizontalLayout` | `BatchEditCommitTests`, `KeyboardAvoidanceTests` |
| `day-MM-YYYY` | `PCCalendarDayModel.accessibilityID` | every day-tap UI test |
| `New batch`, `Save`, `Delete event`, `Delete batch` | `accessibilityLabel` | `BatchEditCommitTests` |

## Expected deltas per stage

Stages 1-5 are renames, additions and deletions of types that no UI test touches, so
the count must stay at exactly 229 unit / 29 UI. Test counts may only change in ways
the stage's own row in `REFACTOR_PLAN.md` §10 predicts — principally Stage 6 onward,
where the four view-model test suites are removed and replaced by reducer tests.

| After stage | Unit | UI | Note |
|---|---:|---:|---|
| 1-5 | 229 | 29 | unchanged; `AddEditListViewModelTests` renamed, not removed |
| 6 | 229 − 28 + reducer tests | 29 | the four VM suites go; reducer suites arrive |
| 7-8 | stable | 29 | |
| 9 | stable | 29 + new | new multi-day UI scenario |
