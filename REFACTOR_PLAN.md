# Refactor Plan: PinCal Architecture Cleanup & Single-Batch Assembler

## Overview

Combined three-part refactor addressing: (1) naming clarity, (2) value-type view models (SF*), and (3) single-batch assembler pattern for `PCEventsSelectionManager`. Follows Swift conventions (protocol-oriented, value types, no `I*` prefixes).

---

## 1. Rename & Semantic Alignment

### Files to Rename
| Old | New |
|-----|-----|
| `AddEditListView.swift` | `AddEditEventListView.swift` |
| `AddEditListViewModel.swift` | `AddEditEventListViewModel.swift` |

### References to Update
- `AddEditEventBatchView.swift` (line 42)
- All internal references to `AddEditListView`/`AddEditListViewModel`
- Test files: `AddEditListViewModelTests.swift`, `EventBatchCreationTests.swift`

### Compatibility Shim
```swift
// Temporary — remove after full migration
typealias AddEditListView = AddEditEventListView
typealias AddEditListViewModel = AddEditEventListViewModel
```

---

## 2. SF* Value-Type View Model Wrappers

### New Files
| File | Purpose |
|------|---------|
| `SFEvent.swift` | View-model struct wrapper over `EventDataSource` |
| `SFEventBatch.swift` | View-model struct wrapper over `EventBatchDataSource` |

### Design: Value Types, Not `@Observable`
```swift
// SFEvent.swift (in SingleCalendarFeature/Model/)
public struct SFEvent: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String { didSet { /* placeholder sync if needed */ } }
    public var color: String
    public var date: Date
    public let timestamp: UUID?
    
    // Default name for newly created events (e.g., via toggleDay in BatchAssembler)
    static let defaultNewEventName = "New event"
    
    // Derived/computed properties for views
    var formattedTime: String { date.formatted(date: .omitted, time: .shortened) }
    var isEdited: Bool { id != 0 }
    
    init(from source: EventDataSource) {
        self.id = source.id
        self.name = source.name
        self.color = source.color
        self.date = source.date
        self.timestamp = source.timestamp
    }
    
    // Convenience init for new events — sets name to "New event" placeholder
    init(newEventAt date: Date, color: String = "") {
        self.id = 0
        self.name = SFEvent.defaultNewEventName
        self.color = color
        self.date = date
        self.timestamp = UUID()
    }
    
    func toDataSource() -> EventDataSource {
        EventDataSource(id: id, name: name, date: date, color: color, timestamp: timestamp)
    }
}

// SFEventBatch.swift (in SingleCalendarFeature/Model/)
public struct SFEventBatch: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String
    public var colorName: String
    public var events: [SFEvent]
    public var date: Date?
    public let timestamp: UUID?
    
    // View-specific logic
    var isEmpty: Bool { events.isEmpty }
    var eventCount: Int { events.count }
    var firstEventDate: Date? { events.map(\.date).min() }
    
    init(from source: EventBatchDataSource) {
        self.id = source.id
        self.name = source.name
        self.colorName = source.colorName
        self.events = source.events.map(SFEvent.init)
        self.date = source.date
        self.timestamp = source.timestamp
    }
    
    func toDataSource() -> EventBatchDataSource {
        EventBatchDataSource(
            id: id,
            name: name,
            colorName: colorName,
            events: events.map(\.toDataSource),
            date: date,
            timestamp: timestamp
        )
    }
}
```

### Migration Rules
- `*DataSource` (CorePersistence) → Pure DTOs for persistence, serialization, network transfer
- `SF*` (SingleCalendarFeature) → Value-type view models with UI logic, formatting, derived state

### Files to Update
| File | Changes |
|------|---------|
| `AddEditEventListViewModel.swift` | Return `[SFEvent]` instead of `[EventDataSource]` |
| `AddEditEventBatchListViewModel.swift` | Use `SFEventBatch` / `SFEvent` |
| `AddEditEventBatchViewModel.swift` | Use `SFEventBatch` / `SFEvent` |
| `AddEditEventViewModel.swift` | Use `SFEvent` |
| `PCEventsSelectionManager.swift` | Internally use `SFEvent`/`SFEventBatch`, expose `*DataSource` for persistence boundary |
| `SingleCalendarModel.swift` | Use `SFEvent`/`SFEventBatch` |
| View files | Consume `SF*` types |

---

## 3. PCEventsSelectionManager — Single-Batch Assembler with Protocol Abstractions

### Current Violations (Prioritized)
| Principle | Issue |
|-----------|-------|
| **SRP** | Manages events, batches, calendar (yearModel), day selection mode, persistence, color, merge logic |
| **DIP** | Depends on concretions (`PCCalendarDataProvider`, `PCCalendarDaySelectionManager`, `CalendarCache`), not abstractions |
| **LSP** | No abstraction — concrete types throughout |
| **ISP** | Single giant interface; callers depend on methods they don't use |

### Proposed Decomposition (CalendarModel Unchanged)

```
┌─────────────────────────────────────────────────────────────┐
│                PCEventsSelectionManager (Facade)            │
│  - Composes EventStore, BatchStore, CalendarModel           │
│  - Exposes single-batch assembler API                       │
└──────────────┬──────────────────────────────────────────────┘
               │
   ┌─────────────▼─────────────┐      ┌─────────────────────┐
   │        EventStore         │      │    BatchStore       │
   │  (events, colors,        │      │  (batches, merge,   │
   │   timestamps, isSameDay) │      │   persist)          │
   └─────────────┬─────────────┘      └─────────────┬─────────┘
                 │                            │
        ┌────────▼────────┐          ┌────────▼────────┐
        │   CalendarModel │          │   (registry)    │
        │   yearModel,    │          │   batches,      │
        │   day markers   │          │   persistedIDs  │
        └─────────────────┘          └─────────────────┘
```

### New Protocols (`*able` Suffix, Swift Convention)

```swift
// In SingleCalendarFeature/Model/Protocols/
protocol EventStoreable: AnyObject {
    var events: [SFEvent] { get set }
    var selectedColor: PCColorOption? { get set }
    func prepare(with events: [SFEvent])
    func add(_ event: SFEvent)
    func remove(at indices: IndexSet)
    func apply(_ event: SFEvent)
    func setColor(_ color: PCColorOption?)
    func isSameDay(_ event: SFEvent, _ date: Date) -> Bool
}

protocol BatchStoreable: AnyObject {
    var batches: [SFEventBatch] { get }
    func commit(_ batch: SFEventBatch)
    func delete(_ batches: [SFEventBatch])
    func batch(withId: Int64) -> SFEventBatch?
    func batches(for day: Date) -> [SFEventBatch]
}
```

### Implementation Classes (Conforming to Protocols)

| Class | Responsibility |
|-------|----------------|
| `EventStore` | Event CRUD, color propagation, timestamp management, `isSameDay` |
| `BatchStore` | Batch merge keys, persistence coordination, `persistedIDsByPendingTimestamp` |
| `CalendarModel` | **Unchanged** — year model lifecycle, day markers, column count |
| `PCEventsSelectionManager` | **Facade** composing `EventStore`, `BatchStore`, `CalendarModel` |

### Dependency Injection (Protocols, Not Concretions)

```swift
public init(
    eventStore: EventStoreable = EventStore(),
    batchStore: BatchStoreable = BatchStore(),
    calendarModel: CalendarModel = CalendarModel(),
    dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
    daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager(),
    cache: CalendarCache? = nil
)
```

### New Public API (Assembler Facade)

```swift
// MARK: - Assembly Lifecycle

/// Start assembling a brand new batch.
func startNewBatch() {
    currentBatch = BatchAssembly(source: .new())
    daySelectionManager.selectionMode = .multiple
    daySelectionManager.selectedDays = []
    setupCalendar()
}

/// Start assembling by editing an existing batch.
func startEditingBatch(_ batch: SFEventBatch) {
    currentBatch = BatchAssembly(
        events: batch.events.map { $0 },  // copy
        color: batch.colorName.isEmpty ? nil : PCColorOption(batch.colorName),
        source: .existing(batch),
        originalBatch: nil  // or converted from EventBatchDataSource
    )
    daySelectionManager.selectionMode = .multiple
    daySelectionManager.selectedDays = Set(batch.events.map(\.date))
    setupCalendar()
}

/// Finish assembly — returns the assembled batch ready for commit.
func finishBatch() -> SFEventBatch? {
    guard var assembly = currentBatch else { return nil }
    let batch = assembly.toSFBatch()
    currentBatch = nil
    daySelectionManager.selectionMode = .single
    return batch
}

/// Discard assembly without committing.
func cancelBatch() {
    currentBatch = nil
    daySelectionManager.selectionMode = .single
}
```

### Assembly State (`BatchAssembly`)

```swift
struct BatchAssembly {
    var events: OrderedSet<SFEvent> = []  // Uses OrderedSet for unique-items with order preservation
    var color: PCColorOption?
    var source: BatchSource
    let originalBatch: SFEventBatch?  // nil for new batch, for diff
    
    enum BatchSource {
        case new(timestamp: UUID = UUID())
        case existing(SFEventBatch)
    }
    
    var isEditingExisting: Bool {
        if case .existing = source { return true }
        return false
    }
    
    var pendingTimestamp: UUID? {
        if case .new(let ts) = source { return ts }
        return originalBatch?.timestamp
    }
    
    func toSFBatch() -> SFEventBatch {
        SFEventBatch(
            id: originalBatch?.id ?? 0,
            name: originalBatch?.name ?? "",
            colorName: color?.colorName ?? "",
            events: events,  // OrderedSet conforms to Sequence, convertible or directly used
            date: events.map(\.date).min(),
            timestamp: pendingTimestamp
        )
    }
}
```

**Note:** Requires adding `OrderedSet` as a dependency (e.g., via Swift Package `swift-collections` or similar). All event array references in the assembler and view models should use `OrderedSet` for deterministic ordering and uniqueness.

---

### Assembly Mutations (called by BatchEditor / EventEditor)

```swift
/// Add/remove day from assembly (calendar day tap).
/// - Note: Toggling works independently of whether a batch color has been selected yet.
///   The `color` property on the assembly is optional and is applied separately (e.g., via
///   `setBatchColor(_:)`). Toggling days on/off does not require a color to be set first.
func toggleDay(_ date: Date) {
    guard var assembly = currentBatch else { return }
    if assembly.isSameDay(date) {  // via EventStoreable
        assembly.events.removeAll { $0.date.matches(date) }
    } else {
        let newEvent = SFEvent(newEventAt: date, color: assembly.color?.colorName ?? "")
        assembly.events.append(newEvent)
    }
    assembly.events.sort { $0.date < $1.date }
    currentBatch = assembly
    updateYearModel()
    onEventsChanged?()
}

/// Apply edited event from EventEditor.
func applyEditedEvent(_ event: SFEvent) {
    guard var assembly = currentBatch else { return }
    if let idx = assembly.events.firstIndex(where: { $0.timestamp == event.timestamp }) {
        assembly.events[idx] = event
    } else {
        assembly.events.append(event)
    }
    assembly.events.sort { $0.date < $1.date }
    currentBatch = assembly
    updateYearModel()
    onEventsChanged?()
    onEventApplied?()
}

/// Update batch color (propagates to all events).
func setBatchColor(_ color: PCColorOption?) {
    guard var assembly = currentBatch else { return }
    assembly.color = color
    if let color {
        assembly.events = assembly.events.map { $0.withColor(color.colorName) }
    }
    currentBatch = assembly
    updateYearModel()
    onEventsChanged?()
}
```

### Assembly Logic Notes

**Point 3 — Date-Matching Sufficiency for Event Removal**

The `toggleDay` removal uses `assembly.events.removeAll { $0.date.matches(date) }`, which matches events by date alone. This is sufficient for the intended use case because:

- In normal batch assembly flow, each calendar day typically has **at most one event** toggled on/off at a time.
- Events are sorted by date, and the `isSameDay` check (via `EventStoreable`) compares date components.
- If a batch genuinely needs multiple events on the same date, a secondary `timestamp` check could be added, but the current design assumes date‑unique per‑day toggling.
- **Conclusion:** `.matches(date)` check is adequate for the planned flow; a timestamp guard is unnecessary unless multi‑event‑per‑day becomes a requirement.

**Point 4 — Deselecting the Initially Tapped Day (Sequence Safety)**

User scenario: user taps a day in the calendar → `BatchAssembly` initialized with an event for that date. Later, the user selects other days, then deselects the originally tapped day.

- The `toggleDay(_:)` function removes **all** events whose date matches the tapped date via `removeAll { $0.date.matches(date) }`.
- Since the initially tapped day’s event has a unique date (or is the only event on that date), it is removed correctly.
- All other events (selected in the interim) remain in the assembly untouched, because their dates do not match the tapped date.
- **Result:** The batch continues normally — the first‑tapped event is removed, and the other selected days persist. No special-casing or state‑resetting is required beyond the regular `toggleDay` call.

---
### Registry (Unchanged API, Operates on Committed Batches)

```swift
func commit(_ batch: SFEventBatch) { ... }  // converts to EventBatchDataSource for persistence
func deleteBatches(_ batches: [SFEventBatch]) { ... }
func batch(withId: Int64) -> SFEventBatch? { ... }
func batches(for day: Date) -> [SFEventBatch] { ... }
```

### Calendar Delegation

```swift
var yearModel: PCCalendarYearModel { calendarModel.yearModel }
func setupCalendar() { calendarModel.setup() }
func switchYear(to: Int) { calendarModel.switchYear(to) }
func setScrollTargetMonth(to: Date?) { calendarModel.setScrollTargetMonth(to) }
var numberOfColumns: Int { get { calendarModel.numberOfColumns } set { calendarModel.numberOfColumns = newValue } }
```

---

## 4. Migration Steps

| Step | Action |
|------|--------|
| **1** | Rename `AddEditListView` → `AddEditEventListView` + `ViewModel` |
| **2** | Add `SFEvent.swift` / `SFEventBatch.swift` value-type wrappers |
| **3** | Add `EventStoreable` / `BatchStoreable` protocols in `Model/Protocols/` |
| **4** | Extract `EventStore` / `BatchStore` as protocol conformances |
| **5** | Make `PCEventsSelectionManager` compose protocols (keep `CalendarModel` as-is) |
| **6** | Update call sites to use protocol types where possible |
| **7** | Add `BatchAssembly` struct + assembler API (`startNewBatch`, `finishBatch`, etc.) |
| **8** | Replace `prepare(with:)` → callers use `startNewBatch()` / `startEditingBatch(_:)` |
| **9** | Replace `addEvent/removeEvent/apply` → `toggleDay(_:)` / `applyEditedEvent(_:)` |
| **10** | `commit(_:)` now called by BatchEditor with `finishBatch()` result |
| **11** | Update `AddEditEventBatchViewModel`, `AddEditEventBatchListViewModel`, `SingleCalendarModel` |
| **12** | Add unit tests: `BatchAssemblyTests`, `EventStoreTests`, `BatchStoreTests` |
| **13** | Keep existing `PCEventsSelectionManagerTests` as integration tests |

---

## 5. Caller Changes

| Caller | Old API | New API |
|--------|---------|---------|
| `AddEditEventBatchViewModel` | `prepare(with:)` → user taps days → `commit(batch)` | `startNewBatch()` / `startEditingBatch(_:)` → user taps days → `finishBatch()` → `commit(_:)` (with `SFEventBatch`) |
| `AddEditEventBatchListViewModel` | reads `events` | reads `eventStore.events` (via protocol) |
| `AddEditEventViewModel` | `apply(_:)` on manager | `applyEditedEvent(_:)` on manager (or `eventStore.apply(_:)`) |
| `SingleCalendarModel` | `setCalendar(id:, batches:)` | unchanged (registry API via `BatchStoreable`) |

---

## 6. Benefits

1. **Explicit assembly lifecycle** — can't accidentally commit half-assembled state
2. **Single responsibility** — assembly vs registry vs calendar truly separated
3. **Testable** — `BatchAssembly` is a pure value type; `finishBatch()` returns immutable result
4. **No implicit state** — `events` array no longer floats freely; lives inside `currentBatch`
5. **Clear ownership** — `BatchEditor` owns assembly lifecycle; `SingleCalendarModel` owns registry; `EventStore` owns event data
6. **Protocol-driven** — DIP satisfied: manager depends on `EventStoreable`/`BatchStoreable`, not concretions
7. **Value-type view models** — `SFEvent`/`SFEventBatch` are testable, hashable, sendable structs with derived UI state

---

## 7. Testing Strategy

| Test Tier | Scope |
|-----------|-------|
| **Unit** | `BatchAssembly` init, `toSFBatch()` conversions, `isEditingExisting`, `pendingTimestamp` |
| **Unit** | `EventStoreable` protocol conformance (`EventStore`) — isolated from SwiftUI |
| **Unit** | `BatchStoreable` protocol conformance (`BatchStore`) — persistence logic |
| **Feature** | `startNewBatch()` → `toggleDay()` → `finishBatch()` → `commit()` end-to-end on manager |
| **Integration** | Full `PCEventsSelectionManager` with real `PCCalendarDataProvider` + `PCCalendarDaySelectionManager` (run less frequently) |

---

## 7. Unidirectional Flow Integration (BatchEditor State Management)

### Intent

Replace view-level booleans (`isCancelled`, `onDisappear` conditionals) with a **pure reducer** that drives state transitions from a single source of truth. The View only **sends Actions**; the **Reducer** produces new State. This makes batch lifecycle (cancel vs. commit) predictable, testable, and debuggable.

### New Types

#### `BatchEditorState` — encapsulates assembly intent

```swift
public enum BatchEditorState: Equatable {
    case idle              // no batch in progress
    case assembling(BatchAssembly)   // user selecting days/color
    case committed(EventBatchDataSource)  // batch saved/persisted
    case cancelled         // user dismissed via back — no persistence
}
```

#### `BatchEditorAction` — the only way to mutate state

```swift
public enum BatchEditorAction {
    case toggleDay(Date)                // calendar day tap
    case changeColor(PCColorOption)     // color picker selection
    case backButtonTapped               // user wants to discard
    case doneButtonTapped               // user wants to save/commit
}
```

#### `BatchEditorStore` — observable store with reducer

```swift
@Observable
final class BatchEditorStore {
    private(set) var state: BatchEditorState = .idle
    private let reducer: (BatchEditorState, BatchEditorAction) -> BatchEditorState

    init(
        initialState: BatchEditorState = .idle,
        reducer: @escaping (BatchEditorState, BatchEditorAction) -> BatchEditorState = { ... }
    ) {
        self.state = initialState
        self.reducer = reducer
    }

    // Public API — view sends actions, never mutates state directly
    func send(_ action: BatchEditorAction) {
        self.state = reducer(self.state, action)
    }
}
```

#### Reducer — pure function, fully testable

```swift
// In a separate file, e.g. BatchEditorReducer.swift
let batchEditorReducer: (BatchEditorState, BatchEditorAction) -> BatchEditorState = { state, action in
    var newState = state

    switch action {
    case let .toggleDay(date):
        guard case .assembling(var assembly) = newState else { return .idle }
        if assembly.isSameDay(date) {
            assembly.events.removeAll { $0.date.matches(date) }
        } else {
            let newEvent = SFEvent(id: 0, name: "", date: date,
                                   color: assembly.color?.colorName ?? "", timestamp: UUID())
            assembly.events.append(newEvent)
        }
        assembly.events.sort { $0.date < $1.date }
        currentBatch = assembly  // mutate manager's assembler state
        return .assembling(assembly)

    case .backButtonTapped:
        // Cancel — clear assembly, reset selection mode
        manager.cancelBatch()     // from the refactoring plan
        return .cancelled

    case .doneButtonTapped:
        // Commit — finish assembly and persist
        if let batch = manager.finishBatch() {
            manager.commit(batch)  // persists as EventBatchDataSource
            return .committed(batch)
        }
        return .idle                // finishBatch() returned nil — nothing to persist
    }

    return newState
}
```

### View Integration — Minimal Logic

```swift
struct BatchEditor: View {
    // Store is typically provided via @Bindable or dependency injection
    @Bindable var store: BatchEditorStore

    var body: some View {
        VStack(spacing: 20) {
            // UI reads state — never binds to boolean flags
            BatchContentView(state: store.state)

            // Actions dispatched via UI interactions — no `isCancelled` tracking
            HStack {
                Button("Back") { store.send(.backButtonTapped) }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Done") { store.send(.doneButtonTapped) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { /* store state already reflects initial idle state */ }
    }
}
```

### Benefits vs. Old Approach

| Concern | Old Approach | UDF Approach |
|---------|-------------|--------------|
| **View tracks `isCancelled`** | ❌ Boolean flag in View | ✅ Eliminated — state in Store |
| **`onDisappear` conditional logic** | ❌ `if isCancelled { cancelBatch() }` | ✅ Reducer handles transition; `onDisappear` becomes a no-op or simple safety-net |
| **Cancel vs. commit logic scattered** | ❌ Across View + Manager | ✅ Single reducer — one source of truth |
| **Testability** | ❌ Integration-style, hard to isolate | ✅ Reducer is pure `(State, Action) -> State` — unit-testable in isolation |
| **Debuggability** | ❌ Scattered state changes | ✅ Log every `send(action)` — full history reconstructible |
| **Modularity** | ❌ View knows about manager internals | ✅ View only knows `Store` API — completely decoupled |

### Migration Path

| Step | Action |
|------|--------|
| **1** | Add `BatchEditorState.swift`, `BatchEditorAction.swift`, `BatchEditorStore.swift`, `BatchEditorReducer.swift` to feature module |
| **2** | Refactor `BatchEditor` View to use `@Bindable var store` and dispatch actions via UI taps |
| **3** | Replace `isCancelled` boolean + `onDisappear` conditional with `store.send(.backButtonTapped)` / `store.send(.doneButtonTapped)` |
| **4** | Add unit tests for `batchEditorReducer` covering all action → state transitions |
| **5** | Remove old `onDisappear` batch-cancel logic (kept only as redundant safety-net if desired) |

### How This Integrates With Existing Plan

| Existing Phase | UDF Integration Touchpoint |
|---------------|---------------------------|
| **Phase 4** (Assembler) | `BatchAssembly` state transitions (`toggleDay`, `backButtonTapped`, `doneButtonTapped`) now go through the **reducer** instead of View-level booleans |
| **Phase 5** (Caller Updates) | View models/`BatchEditor` now call `store.send(action)` — the reducer handles `currentBatch` mutations, `finishBatch()`, `cancelBatch()` |
| **Phase 6** (Testing) | New unit tests for `batchEditorReducer` are added alongside existing `BatchAssemblyTests`/`EventStoreTests` |

### Result

- **Zero** `isCancelled` flags in View code
- **Zero** `onDisappear` conditionals checking booleans
- **Single source of truth** for batch lifecycle state
- **Predictable**: back always → `.cancelled`, done always → `.committed` (or `.idle` if nil)
- **Testable**: reducer covered 100% by pure-function unit tests
- **Debuggable**: every state change is an explicit action dispatched through a central point

---

1. **Rename** (mechanical, safe, immediate win)
2. **SF* Wrappers** (foundation: value types, computed UI state; enables later protocol work)
3. **Protocols** (`EventStoreable`/`BatchStoreable`, `CalendarModel` intact) — DIP foundation
4. **Assembler** (`BatchAssembly` + lifecycle methods) — consumes protocols, not concretions
5. **Caller Updates** (view models, models wired to protocol types)
6. **Testing** (unit → feature → integration)
7. **UDF Integration** (unidirectional flow for BatchEditor — state enums, store, reducer, action dispatching; eliminates `isCancelled` flag and `onDisappear` conditional logic)

This ordering ensures each phase builds on a solid architectural foundation while delivering incremental value. The `BatchAssembly` assembler is a **consumer** of protocols, not a standalone addition — avoiding the "SOLID-lite" anti-pattern where protocols are defined but not properly injected. Phase 7 introduces unidirectional flow so that UI state transitions (back vs. done) are driven by a pure reducer, not view-level booleans.

## Git Branching Strategy

Each phase executes on its own feature branch to enable isolated development, independent reviews, and granular rollbacks:

| Phase | Branch | Description |
|-------|--------|-------------|
| **0** | `feature/batcheditor/stage-0` | Initial repo state — no changes. Baseline for all subsequent branches. |
| **1** | `feature/batcheditor/stage-1` | Rename `AddEditListView` → `AddEditEventListView` + ViewModel (mechanical, safe win). |
| **2** | `feature/batcheditor/stage-2` | Add `SFEvent.swift` / `SFEventBatch.swift` value-type wrappers; update view models. |
| **3** | `feature/batcheditor/stage-3` | Add `EventStoreable` / `BatchStoreable` protocols; extract `EventStore` / `BatchStore`. |
| **4** | `feature/batcheditor/stage-4` | Make `PCEventsSelectionManager` compose protocols; keep `CalendarModel` intact. |
| **5** | `feature/batcheditor/stage-5` | Caller updates: view models/models wired to protocol types; API surface stabilizes. |
| **6** | `feature/batcheditor/stage-6` | Testing: unit tests for `BatchAssembly`, `EventStore`, `BatchStore`; feature tests end-to-end. |
| **7** | `feature/batcheditor/stage-7` | UDF Integration: add `BatchEditorState`/`Action`/Store/Reducer; eliminate `isCancelled`/`onDisappear` conditionals. |

### Branch Workflow

1. **Start from `main`** (or `develop`) — always reset to Stage 0 baseline before beginning a new phase.
2. **Create branch** `feature/batcheditor/stage-N` from the completed Stage N-1 branch (or `main` for Stage 1).
3. **Implement only the phase's deliverables** — no cross-phase leakage.
4. **Open PR** against the Stage N-1 branch (or `main`) for review.
5. **Merge PR**, then optionally delete the stage branch (kept for history if needed).
6. **Proceed to next stage** — create `feature/batcheditor/stage-(N+1)` from the newly merged code.

### Benefits of This Strategy

- **Isolation** — each phase's changes are encapsulated; no unintended side effects on other phases.
- **Parallel work** — different teams can work on non-dependent phases simultaneously (e.g., Stage 2 SF* wrappers and Stage 3 protocols can start once Stage 1 is merged).
- **Granular rollback** — if a phase introduces a regression, revert only that stage's branch.
- **PR hygiene** — each PR has a focused scope (one phase), making reviews faster and more thorough.
- **Safety net** — Stage 0 branch is the immutable baseline; can always reset to it if a later stage goes badly wrong.

### Example Branch Commands (bash)

```bash
# From main, reset to baseline
git checkout main
git pull origin main

# Create Stage 1 branch from baseline
git checkout -b feature/batcheditor/stage-1

# After Stage 1 is done and reviewed, merge to main
git checkout main
git merge --no-ff feature/batcheditor/stage-1
git push origin main

# Create Stage 2 branch from new main
git checkout -b feature/batcheditor/stage-2 main

# ...repeat for stages 3-7
```

This branching strategy works hand-in-hand with the 7-phase execution order, ensuring that each architectural increment is delivered, reviewed, and stabilized independently before the next is attempted.

---