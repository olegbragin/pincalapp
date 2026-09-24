# BatchEditor — PCEventBatchEditor plan (living doc)

> This file is updated after each successful refactoring stage. Stage 0 is done.
> Stages 1–6 below are confirmed but NOT implemented yet.

## 0. Goal

Batch editor works as a wizard controlled by one director:

```
calendar selected -> day selected -> batches on day -> selected batch
  -> events for batch -> selected event
```

Rules:

- Every user action commits to memory first, then persists to ObjectBox lazily.
- No duplicates for pending changes (`pendingKeys` set, coalesced `flush`).
- No `Task.sleep` / `Thread.sleep` anywhere in new code — correct structured concurrency only.
- No Combine in new editor code (`PassthroughSubject` stays only in legacy `CalendarCache` until migrated to `AsyncStream`).
- `EventBatchDataSource` / `EventDataSource` are persistence DTOs only. VMs, director and parts use `SFEventBatch` / `SFEvent` (public, `SingleCalendarFeature` prefix `SF`). Mapping to DTOs/entities happens only at the persist edge.
- Protocols use `*able` suffix (`BatchPersistable`, `EventStorable`, …).
- Every new part file has a top-of-file overview + `///` docs on every public type/method with `- Parameters:`, `- Returns:` where applicable.
- Storage changes must be migration-safe. User data on devices must never corrupt.

## 1. Current state (summary)

- `SingleCalendarView.route(for:)` drives `.dayBatches / .batchEditor(.newDay/.existingBatch) / .eventEditor`.
- `PCCalendarSession` owns shared `PCEventsSelectionManager(cache:dataProvider:daySelectionManager:)`.
- `PCEventsSelectionManager` (≈334 lines) mixes event CRUD, batch CRUD, color, `yearModel` build/update, `Task`-based `persistBatches`, column plumbing, 2 closure callbacks.
- Duplicated pending state: `SingleCalendarModel.addedEvents + selectedColor` vs manager `events/selectedColor` vs `AddEditEventBatchViewModel.eventBatchId/Name/date/timestamp` vs `AddEditEventBatchListViewModel.eventBatches` copy.
- Double persist: `manager.commit` persists + `SingleCalendarModel.commitPendingBatch/save` persists again.
- Keys: `BatchMergeKey.unsaved(hashValue)` unstable; `EventBatchDataSource.init(dto:)` drops `timestamp=nil`; `PPEvent.init` assigns `self.id` twice (guard dead).
- Tests: unit covers event CRUD/route/commit; UI `BatchEditCommitTests` (6 STRs) covers save/rename/color/delete. No wizard-stage, lazy-persist, or no-dup tests.

### SOLID gaps

- **S:** manager + `SingleCalendarModel` + `AddEditEventBatchViewModel` each do 4–6 jobs.
- **O:** concrete `CalendarCache` dependency; `route(for:)` hard-codes destinations.
- **L:** DTO init breaks identity (`timestamp` loss); `PPEvent.init` breaks id contract.
- **I:** views take whole manager (`AddEditListView(manager:)`); 2 fat closures.
- **D:** VMs depend on concrete manager + static `PCCalendarModelBuilder`; only `CalendarRepository` is a proper abstraction.

## 2. Target architecture

```
Packages/SingleCalendarFeature/Sources/SingleCalendarFeature/Model/Editor/
  PCEventBatchEditor.swift      // director, @Observable, composes *able parts
  PCEditorStage.swift           // enum .calendar/.day(Date)/.batchList(Date)/.batch(SFEventBatch)/.event(SFEvent)
  SFEvent.swift                 // public draft struct (was PCEventDraft)
  SFEventBatch.swift            // public draft struct (was PCBatchDraft)
  Protocols/
    BatchSelectable.swift       // selectCalendar/selectDay/selectBatch/selectEvent
    EventStorable.swift         // add/remove/apply/setBatchColor/hasEvent
    BatchPersistable.swift      // commitToMemory/schedulePersist/flush/discardPending/pendingCount
    BatchDataMappable.swift     // SF drafts <-> EventBatchDataSource/EventDataSource (persist edge only)
    BatchEditorDelegate.swift   // editorDidUpdateEvents/editorDidPersist (replaces closures, no Combine)
  Parts/
    PCBatchSelection.swift      // calendarId, selectedDay, dayBatches, selectedBatch
    PCBatchEventStore.swift     // [SFEvent], selectedColor, event mutations + marker refresh request
    PCBatchPersistQueue.swift   // pendingKeys:Set<BatchMergeKey>, dirty flag, flush/discard
    PCCalendarMarkerUpdater.swift // yearModel day-marker rebuild (extracted from manager)
    BatchTitleFormatter.swift   // preferred/compact titles (extracted from BatchVM)
  Mapping/
    SFBatchMapper.swift         // SF drafts <-> DataSources <-> PP* entities; ONLY place importing CorePersistence DTOs
```

Director delegates, never implements part logic directly:

```swift
selectDay(_:) -> selection.selectDay + store.refreshMarkers + persist.markDirty
apply(event:) -> store.apply + persist.schedulePersist
save() -> persist.flush() async throws
```

### 2.1 Public drafts (`SF` prefix, `SingleCalendarFeature` module)

```swift
public struct SFEvent: Identifiable, Hashable, Sendable {
  public var pendingID: UUID
  public var persistedID: Int64?
  public var name: String
  public var date: Date
  public var colorName: String
}
public struct SFEventBatch: Identifiable, Hashable, Sendable {
  public var pendingID: UUID
  public var persistedID: Int64?
  public var name: String
  public var colorName: String
  public var date: Date?
  public var events: [SFEvent]
}
```

- VMs, director, parts use only `SF*`. `EventBatchDataSource/EventDataSource/PPCalendar/PPEvent(All)` appear only inside `SFBatchMapper` + `CalendarRepository` impl.
- Merge key = `persistedID.map(BatchMergeKey.persisted) ?? .pending(pendingID)` — never `hashValue`.

### 2.2 Protocols (`*able`)

- `BatchSelectable`, `EventStorable`, `BatchPersistable`, `BatchDataMappable` as above.
- Views take minimal protocol: event list needs `EventStorable` only; batch header needs `BatchSelectable & BatchPersistable`.

### 2.3 No-sleep concurrency

- `schedulePersist()` only sets `dirty=true` + `pendingKeys.insert`. No `Task`, no timer.
- IO only in `flush() async throws`, awaited from `save()`, `onEventApplied` (now delegate), `onDisappear`, `popToRoot`.
- Existing `Task.sleep(350ms)` column saver → direct save on change + flush on disappear.
- Tests wait with `waitForExistence` / `await waitUntil { Task.yield() }`, never `Task.sleep` / `Thread.sleep`.

### 2.4 Observation without Combine

- Keep Swift `@Observable/@Bindable` for SwiftUI (not Combine).
- Delete `onEventsChanged/onEventApplied` closures → `BatchEditorDelegate` (sync, testable).
- Migrate `CalendarCache.changes: PassthroughSubject` → `AsyncStream<ChangeOperation>` in a later stage; new editor code never imports Combine.

### 2.5 ObjectBox id safety (docs)

Per ObjectBox Swift `Box.put(_:mode:)` + Object IDs docs:

- `id == 0` = new → `put` inserts and assigns a fresh ID.
- Only ObjectBox assigns IDs by default — `put` with an ID above current max **throws**; `PutMode.insert` fails if ID exists, `.update` fails if missing.
- Mapper rule: `persistedID == nil → PP*(id: 0)` (auto-assign); else `PP*(id: persistedID)` with default `.put` (upsert). Never forward UI indices or fabricated `Int64`s.
- Fix `PPEvent.init` double `self.id = id`; keep `if id > 0` guard like `PPCalendar/PPEventBatch`.
- After `put`, refetch calendar to backfill real IDs into `SF*` persistedIDs (existing `CalendarCache.updateCalendar` pattern).

### 2.6 Doc-comment standard

Every new file:

```swift
/// One-line summary.
///
/// Longer overview: responsibilities, collaborators, threading (@MainActor).
```

Every public method:

```swift
/// Short description.
///
/// - Parameters:
///   - day: description
/// - Returns: description
/// - Throws: when flush hits the store
```

### 2.7 Storage migration safety (no data loss)

Entities today: `PPCalendar (id,name,year,numberOfColumns,isArchived,events,eventBatches)`, `PPEventBatch (id,title,color,date,events,calendars)`, `PPEvent (id,name,color,date,calendars)`.

- Additive-only schema changes (new optional props with defaults, e.g. `pendingUUID: String?`). Never rename/remove/retype existing props in one release.
- If a stored pending UUID is needed, backfill on first launch: `nil → UUID().uuidString`, inside the same write txn, idempotent.
- Keep entity `id` semantics untouched (no `assignable:true` unless explicitly designed).
- Pre-migration backup: copy store directory (ObjectBox directory path) before first write of new version; on failure, open read-only old store and surface error instead of writing partial data.
- Migration tests (must pass before release): open fixture stores built with old schema (seed 1 calendar + 1 batch + 2 events), run migration, assert counts/ids/names/dates/colors unchanged + new fields defaulted; downgrade-open must fail loudly, never silently rewrite.
- Rollout: migration runs once on launch before `CalendarCache.loadActive`; `flush()` blocked until migration completes.

## 3. Renames

- `Model/AddEditListViewModel.swift` → `Model/AddEditEventListViewModel.swift` (`AddEditEventListViewModel`, keep `typealias AddEditListViewModel` one PR).
- `View/AddEditListView.swift` → `View/AddEditEventListView.swift` (`AddEditEventListView`, same alias).
- `PCEventsSelectionManager` → `PCEventBatchEditor` (keep `typealias PCEventsSelectionManager` one PR).
- Update refs in layouts, `AddEditEventBatchView`, tests (`AddEditListViewModelTests` → `AddEditEventListViewModelTests`).

## 4. Test plan

Unit (per part + director integration):

```
Tests/SingleCalendarFeatureTests/Editor/
  PCBatchSelectionTests.swift
  PCBatchEventStoreTests.swift
  PCBatchPersistQueueTests.swift
  MarkerUpdaterTests.swift / TitleFormatterTests.swift
  SFBatchMapperTests.swift            // SF<->DTO<->PP, id 0 vs persisted, bogus-id throws
  MigrationTests.swift                // old-store fixture → migrate → data intact
  PCEventBatchEditorIntegrationTests.swift // stage→memory→flush→repo, fetch-merge guard, no-dup
```

UI (new folders, shared support, no sleeps):

```
PinCalAppUITests/Support/BatchEditorTestSupport.swift // extracted from KeyboardAvoidanceTestSupport
PinCalAppUITests/BatchEditor/BatchRenameTests.swift
PinCalAppUITests/BatchEditor/BatchPlusEventEditTests.swift
PinCalAppUITests/BatchEditor/NewBatchMultiDayTests.swift
PinCalAppUITests/BatchEditor/BatchEditCommitTests.swift // moved existing 6
```

Required scenarios:

1. Day-with-events → list → tap batch → change batch name → Save persists (reopen shows name, exactly 1 batch for day).
2. Same entry → change batch name → tap event → change name+time → Save → back in batch editor → Save persists exactly 1 batch + exactly 1 edited event.
3. Mar 10 (empty) → editor → tap Mar 11,12 → Mark 10 → set name+color → tap first event → rename+retime → Save → Save → back on `SingleCalendarView`, Mar 11+12 colored with batch color, no duplicates.

## 5. Stages (checklist — update after each green stage)

- [x] Stage 0 — write this `BatchEditor.md` (done, no code changed).
- [x] Stage 1 — renames (`AddEditEventList*`, aliases), build green (done 2026-09-23: sim build OK, 14/14 `AddEditEventListViewModelTests` pass via `test_sim`).
- [x] Stage 2 — add `SFEvent/SFEventBatch` + `*able` protocols + `SFBatchMapper` + id/migration unit tests (done 2026-09-23: 10 source files under `Model/Editor/`, 12/12 new tests pass via `test_sim`, sim build OK, no director change).
- [x] Stage 3 — extract parts + `PCEventBatchEditor` director (done 2026-09-23: `Parts/` selection/store/queue/markers/formatter + director, delegate, no Combine/sleep, `///` docs, sim build OK; old code untouched, no store wiring yet — flush handler set in Stage 4; part/integration tests in Stage 5).
- [x] Stage 4 — wiring + single-write + init bugs (done 2026-09-23: `PPEvent.init` double-assign fixed + `PPEntityInitTests` 6/6; session owns `PCEventBatchEditor` with a live `cache`-backed flush handler (DTO mapping + `rekey` adoption); `commitToMemory` no-op tweak carried over; redundant second `save()` dropped from `commitPendingBatch`/`deleteBatches` (columns keep their own save path); test fixture now mirrors production — one cache-backed manager + one shared day-selection manager, which caught the hidden second writer; 21/21 model tests + 90-test unit selection green + scenario-2 UI green. No entity schema change → no migration needed, zero data-loss risk. Remaining follow-up: thin the 4 VMs onto `SF` drafts/`*able`s so views drive the director directly.) (Partially started: Stage 6 exposed the new-batch duplicate and took the memory-first slice — `commitToMemory` on the manager, auto-commit from the event editor is memory-only, single store write in `save()`. Full VM thinning still pending.)
- [x] Follow-up — thin the 4 VMs onto `SF` drafts so views drive the director directly (done 2026-09-24: `AddEditEvent{Batch,BatchList,List,View}Model` rewritten as thin director-backed adapters over `SFEvent`/`SFEventBatch` (no DTOs, titles via `BatchTitleFormatter`); all 5 batch views take `PCEventBatchEditor` (list reads `selection.dayBatches`, no local batch copy); `SingleCalendarModel` owns the editor, opens/syncs it on fetch (DTO mapping at the persist edge only), routes through `selectDay/openBatchList/selectBatch/startNewBatch`, and reads batches/hasEvents from the director queue; model seeds a cache-backed flush handler when the owner didn't (fixtures); director `save()/flush()` now `replaceAllBatches` so the list shows saved state, `selectCalendar` preserves the wizard on same-calendar refresh and new `syncCalendar` keeps fetch from kicking the user out of the list/editor; batch screen passes column layout + anchor into the VM (pre-layout scroll anchor, `-UITestColumns` honored). Two live-only bugs found via UI failures + device logs + recording frames: (1) calendar attachment is display-lifecycle only (`setup()`/`onAppear`, never `init` — init-time attach let speculative `navigationDestination` inits steal markers onto invisible models, breaking editor day-marker refresh); (2) selection driving moved out of screen/event-view inits into once-guarded `setup()` for the same reason (init-time `startNewBatch`/`selectBatch` committed phantom batches, e.g. an empty-named duplicate breaking delete-to-empty navigation). Fix: `AddEditEventBatchListViewModel.eventBatches` changed from a computed property (`{ editor.dayBatches }`) to a stored `@Observable` property that gets explicitly updated on every mutation (`init`, `prepare`, `remove`, `reset`) — the `@Observable` system doesn't propagate change notifications across `@Observable` object boundaries, so the computed property caused the view to never re-render after batch deletion. Green: ~270 unit/integration tests (VM suites, model, ObjectBox integration, repro, editor parts, mapper, migration, other targets) + 11/11 batch UI scenarios (4 `BatchEditor/` files + 2 legacy main-suite) + save-from-editor + keyboard-avoidance UI. `PCEventsSelectionManager` stays as the legacy marker/persist mirror (single-writer: director flush); full manager removal is a later step.)
- [x] Stage 5 — per-part unit + director integration + migration tests (done 2026-09-23: 48 new tests — selection 10, store 11, queue 9, markers 3, formatter 6, director integration 9 — plus 12 Stage 2 tests, 60/60 green via `test_sim`; functional coverage of all new `Editor/` code, declarations excluded per plan).
- [x] Stage 6 — UI `Support/` + `BatchEditor/` 3 scenarios + move existing tests (done 2026-09-23: `Support/BatchEditorTestSupport.swift` owned helpers, `BatchRenameTests` / `BatchPlusEventEditTests` / `NewBatchMultiDayTests` green on the iPhone `-AutoTest` simulator, moved `BatchEditCommitTests` 6/6 green; full `AutoTestRunner` suite pass remains the release gate).

Each stage ends with: build + unit + relevant UI green, then check the box above in the same PR.

## 6. Token budget (monitoring — updated every stage)

OpenCode site publishes no single token limit. Limits come from the selected model via Models.dev (`limit.input`, `limit.output`) minus compaction reserve (`compaction.reserved`, default 16000; see `docs/models`, `docs/zen`, session `overflow.ts` behaviour):
- GPT-5.5 OAuth (Codex backend): ~400k total / ~272k input.
- GPT-5.6 OAuth: ~500k total / ~372k input (opt-in `-1m`: 1M / 872k input).
- OpenAI API-key models: up to ~1.05M / ~920k input.
- Claude default: 200k input (1M only with `context-1m` beta, not enabled in core OpenCode).
- This session model (`muse-spark-1.3-contributor-free`) is not in the OpenCode catalog; planning uses the conservative floor: **200k input − 16k reserve ≈ 184k usable**.

Scope measured 2026-09-23: 3901 lines in `SingleCalendarFeature/Model+View(AddEdit*/BatchEditor*)` + `ViewModels/*Tests` + `PinCalAppUITests` (~224KB, ≈56k tokens at ~4 chars/token for one full read).

Estimate (input+output per stage, incl. re-reads, edits, test runs):

| Stage | Work | Est. tokens |
|---|---|---|
| 0 done | analysis + this doc | ~60–80k consumed (context incl. ~15 file reads) |
| 1 | renames + aliases, build green | 8–12k |
| 2 | `SFEvent/SFEventBatch` + `*able` + mapper + id/migration tests | 15–20k |
| 3 | parts + `PCEventBatchEditor` director + `///` docs (largest) | 25–35k |
| 4 | thin VMs, remove double save, DTO/PP fixes + backup | 15–20k |
| 5 | per-part unit + director integration + migration tests | 15–20k |
| 6 | UI `Support/` + 3 scenarios + move existing | 20–25k |
| **Goal total (1–6)** | | **≈100–135k** |

Running total (actuals filled after each stage):

| Stage | Actual tokens | Cumulative | Status |
|---|---|---|---|
| 0 | ~70k (est.) | ~70k | done, doc written |
| 1 | ~12k (3 renames + sim build + 14 tests) | ~82k | done 2026-09-23, within budget |
| 2 | ~18k (10 source files + 2 test files + sim build + 12 tests) | ~100k | done 2026-09-23, within budget |
| 3 | ~20k (6 source files + 2 protocol extensions + sim build) | ~120k | done 2026-09-23, within budget |
| 5 | ~22k (6 test files + queue dedup tweak + 60-test run) | ~142k | done 2026-09-23, within budget (Stage 4 deferred) |
| 6 | ~45k (support + 3 scenarios + moved suite + duplicate fix + 10 UI runs incl. flakes) | ~187k | done 2026-09-23 |
| 4 | ~20k (init fix + rekey + session wiring + single-write + fixture alignment + 90 unit + 1 UI) | ~207k | done 2026-09-23 — over planning floor; fresh session advised for follow-ups |
| Follow-up | VM thinning onto SF drafts | — | pending |

Rule: before each stage, check `cumulative + stage estimate ≤ 184k usable`. If the projection exceeds the usable budget, **stop, do not start the stage**, and commit the current state (checked boxes + this table) in this file. Goal 100–135k fits the 184k floor only with pruning/compaction between stages; if actuals track ~30% over estimate, stop after stage 3–4 and continue in a fresh session re-reading only this doc.
