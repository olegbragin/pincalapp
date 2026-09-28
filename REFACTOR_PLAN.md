# Refactor Plan: Batch Assembly as a Unidirectional Pipeline

> **Status:** proposed. Stage 0 is complete. No refactoring code has been written.
>
> **Scope:** `Packages/CoreDomain`, `Packages/CorePersistence`,
> `Packages/CalendarListFeature`, `Packages/SingleCalendarFeature`, plus the
> additive changes in `Packages/DSKit` and `Packages/AppNavigation` they need.
>
> **Five requirements this plan is written against:**
>
> 1. Rename `AddEditListView` / `AddEditListViewModel` to
>    `AddEditEventListView` / `AddEditEventListViewModel`.
> 2. Refactor `PCEventsSelectionManager` into `PCEventSelectionManager` and make it
>    the **only** channel through which the AddEdit flow talks. It behaves like an
>    assembly line: enter from a view or from an existing batch, edit the batch,
>    edit its event list, edit an event, and commit/save from any stage.
> 3. Adopt [Unidirectional flow in Swift](https://swiftwithmajid.com/2023/07/11/unidirectional-flow-in-swift/)
>    for every view involved in batch assembly: views read state and send actions,
>    never mutate.
> 4. Keep the `*DataSource` structs at the data level — inside the cache or the
>    repository, nowhere else. `PCEventSelectionManager` speaks `CalendarEventBatch` and
>    `CalendarEvent`, so all communication is in types the app defines.
> 5. Record a full baseline including the UI suite before starting, and hold every
>    stage to it. See `TEST_BASELINE.md`.
>
> **Naming note:** requirement 2 spells the new type `PCEventSelctionManager`.
> This plan uses the correctly spelled `PCEventSelectionManager`. Say the word if
> the typo is intentional. This type is the "assembler" the rest of this document
> refers to; if you would rather name it for what it does, `PCEventBatchAssembler`
> is the obvious alternative and renaming it now is free.
>
> **Naming note 2:** the domain models are `CalendarEvent` and `CalendarEventBatch`,
> not `SFEvent` / `SFEventBatch`. The `SF` prefix stood for `SingleCalendarFeature`,
> which they no longer live in (§3). The calendar itself is `PinCalendar`, not
> `SCCalendar` and not `Calendar` — a type named `Calendar` in a module that also
> imports `Foundation` shadows `Foundation.Calendar` in every file that sees both,
> and this one owns a `Calendar` inside `PCCalendarDataProvider`.

---

## 1. Naming

| Old | New |
|---|---|
| `AddEditListView` | `AddEditEventListView` |
| `AddEditListViewModel` | `AddEditEventListViewModel` (kept — see §8.1) |
| `PCEventsSelectionManager` | `PCEventSelectionManager` |
| `CalendarDataSource` | **stays** in `CorePersistence`; `PinCalendar` is the abstraction layered above it |
| `AddEditEventBatchListView` | unchanged |
| `AddEditEventBatchScreen` | unchanged |
| `AddEditEventBatchView` | unchanged |
| `AddEditEventView` | unchanged |
| `BatchEditor*Layout` / `BatchEditor*Title` | unchanged |

A `typealias` shim for the two `AddEditList*` names is added in Stage 1 and removed
in Stage 8, so no intermediate branch depends on a broken reference.

### 1.1 Types that go away

| Type | Disposition | Stage | Reason |
|---|---|---|---|
| `EventDataSource`, `EventBatchDataSource` | internal to `CorePersistence` | 3 | Requirement 4 |
| — | nothing | — | `CalendarDataSource` **stays** in `CorePersistence`; see §3.2 |
| `onEventsChanged` / `onEventApplied` closures | deleted | 10 | Last-writer-wins clobbering; replaced by `Action` |
| `BatchEditorSource`, `EventEditorSource` | deleted | 6 | Route payloads move into store state |
| `BatchMergeKey.unsaved(Int)` | deleted | 5 | `hashValue` is not a stable identity |
| `persistedIDsByPendingTimestamp` | deleted | 5 | Replaced by `CalendarEventBatch.persistedID` |
| `SFBatchMapper` in the feature package | deleted | 3 | Mapping belongs in the data layer |

**The four view models are kept.** They become stateless projection facades over the
assembler (§8.1) — views still talk to a view model, never to the store directly.
Net across the four: **-484 lines of view-model code** (244 + 76 + 89 + 75) replaced
by roughly 200 lines of projection, plus **-3 public DTO types** and **+~700 of
state/action/reducer/effect**. Four independent copies of "pending batch state"
collapse into one value.

---

## 2. The assembly line

The store owns a `Stage`. Every user action is an `Action`; the reducer is the
only thing that moves `Stage` forward or back.

```
                      tap day in SingleCalendarView
                                  │  .dayTappedInCalendar
                                  ▼
                  ┌───────────────────────────────┐
                  │  day has batches?              │
                  └───┬───────────────────────┬───┘
                 no  │                       │ yes
                      ▼                       ▼
            ┌──────────────────┐    ┌──────────────────────┐
            │  .batchEditor    │◀───│     .dayList(day)    │
            │                  │    │  AddEditEventBatch…  │
            │ name field       │    │  · tap card → editor │
            │ color picker     │    │  · "+" → editor      │
            │ day calendar     │    │  · trash → commit    │
            │ event list       │    └──────────────────────┘
            │ toolbar Commit   │
            │ toolbar Save     │
            └────────┬─────────┘
                     │ tap event row → .openEvent
                     ▼
            ┌──────────────────────┐
            │  .eventEditor       │
            │  date / name/color  │
            │  Commit  Discard    │
            └──────────────────────┘

  Save from .batchEditor / .eventEditor → commit + pop one level
  Save from .dayList                   → commit (no-op) + pop to root
  Removing every event + Save          → commit deletes the batch, pop to root
  Cancel from any stage                → discard the assembly, pop to root
```

Entry points, all reachable from whichever screen owns the interaction:

| Entry | Action | Where it is triggered |
|---|---|---|
| From a view (day tap) | `dayTappedInCalendar(_:)` | `SingleCalendarView` calendar |
| From a view (new batch on an existing day) | `startNewBatch(on:)` | `AddEditEventBatchListView` "+" button |
| From an existing batch grabbed off the tapped day | `openBatch(pendingID:)` | `AddEditEventBatchListView` card tap |
| From a multi-select session | `confirmMultiSelectTapped` | `SingleCalendarView` toolbar |

`openBatch(pendingID:)` resolves the batch out of `state.batches`; the day the user
tapped is already `state.day`, so the batch is *grabbed from the tapped day*, as
required.

---

## 3. Module boundaries and the data layer

This is requirement 4, and it is the change that makes requirement 2 enforceable.

### 3.1 Target dependency graph

```
  ObjectBox  ──  PP* entities (PPCalendar, PPEventBatch, PPEvent)
                  internal to CorePersistence, never referenced above it
                          │
  CorePersistence ─────────┼────  *DataSource structs
  (persistence)            │      EventDataSource, EventBatchDataSource,
                           │      CalendarDataSource  —  all internal
                           ▼
                   ObjectBoxCalendarStorage      CalendarRepository (protocol)
                           └──────────┬──────────────┘
                                      ▼
                                 CalendarCache
                                      │  CalendarDataSource out
                                      ▼
  PinCalApp (composition root) ──────────┤  the ONLY place that names both
  PinCalApp/Root/                        │  vocabularies.
        EntityMappable (protocol) ───────┤  the pure translation seam.
        RootMapper (concrete)  ──────────┤  stateless, injected, does no I/O.
        CalendarStore  ───────────────────┘  the port. Holds the cache, does I/O,
        PinCalAppApp builds CalendarStore and hands it to PCCalendarSession
                                      │  PinCalendar / [CalendarEventBatch] out
                                      ▼
  CoreDomain ────────────────────────────────────────────
  (domain, no deps) PinCalendar, CalendarEventBatch, CalendarEvent,
               PCCalendarDataProvider, PCCalendar*DataSource,
               protocol CalendarPersisting
                                      ▲
                                      │
  SingleCalendarFeature ──────────────┘
  (feature)    PCEventSelectionManager + State/Action/Reducer/Effects
               SingleCalendarModel, all AddEdit* views
                                      ▲
                                      │
  DSKit (design system) ──────────────┘   PCCalendarYearModel, PCColorOption, …
```

### 3.2 The rule

> `PP*` entities and `CorePersistence/DataSource/*` never appear above the
> `CalendarCache` API. Everything above it speaks the domain models and `CoreDomain` value
> types only. Concretely: no file in `SingleCalendarFeature/Model/` and no file in
> `SingleCalendarFeature/View/` imports `CorePersistence`.

The manager's persistence dependency is the `CalendarPersisting` protocol, declared
in `CoreDomain`. The concrete implementation is `CalendarStore`, in the **app target**.
`CorePersistence` and `CoreDomain` depend on neither each other nor anything else, and
the app is the only place that names both.

Two types, split by what they carry:

| Type | Carries | Job |
|---|---|---|
| `EntityMappable` | — | the protocol for translating between the two vocabularies. Lives only where both type families are visible, so the app target. |
| `RootMapper` | nothing | the production translation. Stateless, and **injected** rather than a static namespace, so a test can substitute it. |
| `CalendarStore` | a `CalendarCache` + an `EntityMappable` | the async read/write side. `CalendarPersisting`, and the only type that touches persistence. |

`PCCalendarSession` does **not** build either, and does not hold the cache. Its
collaborators — the port, the data provider, the column-count resolver, and both shared
managers — all arrive through `init`, so it builds nothing and a test can hand it
whatever it needs. `PinCalAppApp` is the composition root that assembles all of it.

The session exposes `persistence` and nothing storage-shaped, so the storage vocabulary
stops there. The two places that genuinely still need a `CalendarCache` —
`SingleCalendarModel`, and `PCEventsSelectionManager` until it is replaced — get it
injected directly, because that dependency belongs to them rather than to the session.
`PCEventsSelectionManager` is the last cache consumer in the batch flow and it goes in
Stage 9, with `SingleCalendarModel`.

The cache reaches them through the `\.calendarCache` environment key, which the app
already injects. It is **not** injected as a SwiftUI environment object: that requires
`Observable`, and `@Observable` cannot be applied to an actor, which `CalendarCache` is.
Converting it to an `@MainActor @Observable` class would forfeit the isolation its
mutable calendar list depends on, and is not worth it for a non-optional.

```swift
// CoreDomain
public protocol CalendarPersisting: Sendable {
    /// Reads a calendar's management data.
    func calendar(id: Int64) async throws -> PinCalendar?
    /// Reads the event batches assigned to a calendar.
    func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch]
    /// Writes the batch list and column count. The store assigns ids; the caller
    /// never supplies one.
    func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws
}
```

Three methods, and the split matters. A calendar's *management* data and its *batches*
are read by different consumers for different reasons, and `CalendarListFeature` has no
business holding an event graph it never reads — it only ever touched `id`, `name`,
`year`, `numberOfColumns` and `isArchived`. So the calendar comes back as a
`PinCalendar`, five scalars, and the batches come back on their own. A wider port would
put `CalendarCache`'s calendar-list and archive/restore surface back in front of every
caller.

`CalendarDataSource` **stays** in `CorePersistence` rather than being replaced. It is
still the right shape down there: `PPCalendar` holds both `events` and `eventBatches`
relations, so the storage layer genuinely needs the full graph. `PinCalendar` is the
abstraction *above* it, not a replacement for it.

The `CalendarCache.changes` stream stays off the protocol: the manager does not
consume it, and `SingleCalendarModel` keeps its existing Combine subscription to the
concrete `CalendarCache` for calendar metadata, exactly as today.

`CalendarListFeature` is the case that does not get to drop `CorePersistence`. It
needs the concrete `CalendarCache` for the change stream and for the calendar-management
operations — `loadActive`, `loadArchived`, `createCalendar`, `archiveCalendar`,
`restoreCalendar`, `permanentlyDeleteCalendar`, `updateCalendar` — none of which are on
the narrow port, and all of which are that screen's job. So it gains `CoreDomain` for
`PinCalendar` and keeps `CorePersistence` for `CalendarCache`.

The rule in this section is therefore scoped: **no file in `SingleCalendarFeature` imports
`CorePersistence`.** `CalendarListFeature` still does, for the cache and nothing else —
it just stops naming a DTO.

This also gives tests an in-memory `CalendarPersisting` fake, which is what the
write-ordering test in §12.3 needs.

### 3.3 ObjectBox safety: no migration

`PPCalendar.eventBatches` is `ToMany<PPEventBatch>` — an ObjectBox relation, **not**
`[EventBatchDataSource]`. The `*DataSource` structs are plain Swift projections of
the `PP*` entities, not entities themselves. So making them internal, and
retargeting `CalendarCache` at the domain models, changes:

- **not** the ObjectBox schema,
- **not** `EntityInfo-CorePersistence.generated.swift`,
- **not** `model-CorePersistence.json`,
- **not** any stored row.

The `GenerateObjectBox` codegen does not need to re-run and no store migration is
required. User data on device is untouched. This is the fact that makes requirement
4 cheap, and it is the reason the plan does not add a migration stage.

### 3.4 The transformer lives in the composition root

Neither `CorePersistence` nor `CoreDomain` may hold the mapping, or one would have to
depend on the other. So it lives in the **app target**, in `PinCalApp/Root/` beside
`PCCalendarSession`, which is the composition root and already imports both.

```swift
// PinCalApp/Root/EntityMappable.swift — the translation seam.
// One protocol, not three: seven pure functions with a single responsibility
// do not need interface segregation, only three types to pass around.
public nonisolated protocol EntityMappable: Sendable { … }

// PinCalApp/Root/RootMapper.swift — the production translation.
// Stateless, and injected rather than a static namespace, so a test can put a
// different translation in its place. Maps the DTOs, not the PP* entities: the
// DTOs already carry the same information, so CalendarStore can reuse the
// existing, tested write path. `nonisolated` because the app target sets
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
public nonisolated struct RootMapper: EntityMappable {
    static func calendar(_ dto: CalendarDataSource) -> PinCalendar
    static func event(_ dto: EventDataSource) -> CalendarEvent
    static func eventBatch(_ dto: EventBatchDataSource) -> CalendarEventBatch
    static func eventDataSource(from domain: CalendarEvent) -> EventDataSource
    static func eventBatchDataSource(from domain: CalendarEventBatch) -> EventBatchDataSource
}

// PinCalApp/Root/CalendarStore.swift — the concrete port, and the only type
// that holds a cache. Delegates every conversion to its injected EntityMappable.
public nonisolated struct CalendarStore: CalendarPersisting {
    private let cache: CalendarCache
    private let mapper: any EntityMappable
    public init(cache: CalendarCache, mapper: any EntityMappable = RootMapper())
    private let cache: CalendarCache
    public init(cache: CalendarCache)
    // calendar(id:) / eventBatches(calendarID:) / save(...)
}
```

DTO → domain assigns a fresh `pendingID` per row and copies the entity id into
`persistedID`. Domain → DTO writes `persistedID ?? 0`, so ObjectBox sees `0` for a
new row and auto-assigns, and an existing id for an update. `persistedID` is only
ever copied from a row the store returned; nothing fabricates one.

`CalendarDataSource` remains the storage layer's own projection of `PPCalendar` and is
not deleted — see §3.2. `RootMapper` is its counterpart, so `CalendarListFeature` can be
retargeted without the storage layer losing its full graph.

**The protocol, its implementor and the store are all `nonisolated` by necessity, not by
preference.** The app target sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything in it is implicitly
main-actor — including this pure value-to-value mapping, which then cannot satisfy
`CalendarPersisting`'s nonisolated requirements. Opting out also keeps the mapping off
the main actor, where it does not belong.

Two small corrections land in the same stage, both safe because the DTOs are
internal:

- `EventDataSource.timestamp` is deleted. Both DTO initialisers hard-set it to
  `nil`, so it is a session identity that has never been persisted. Its replacement
  is `CalendarEvent.pendingID`, which is what the identity logic in §5 actually uses.
- `PPEvent.init` assigns `self.id` twice — once behind an `if id > 0` guard and once
  unconditionally. Harmless today because `ObjectBox.Id` is `UInt64`, but it
  contradicts the guard next to it and the identical code in `PPCalendar.init` and
  `PPEventBatch.init`. The guard is kept, the stray assignment is removed.

---

## 4. File layout

```
Packages/CoreDomain/Sources/CoreDomain/          [no dependencies]
  PinCalendar.swift                                # management data only, no events
  CalendarEventBatch.swift
  CalendarEvent.swift
  CalendarPersisting.swift                        # the data-layer port
  PCCalendarDataProvider.swift                    # unchanged
  PCCalendar{Year,Month,Week,Day}DataSource.swift # unchanged, domain value types

Packages/CorePersistence/Sources/CorePersistence/
  DataSource/EventDataSource.swift                # internal
  DataSource/EventBatchDataSource.swift           # internal
  CalendarCache.swift                             # conforms to CalendarPersisting
  CalendarRepository.swift                        # still CalendarDataSource internally
  ObjectBoxCalendarStorage.swift                  # maps PP* ⇄ domain models
  DataModels/PP{Calendar,EventBatch,Event}.swift  # unchanged entities
  CalendarCacheEnvironment.swift                  # unchanged

Packages/SingleCalendarFeature/Sources/SingleCalendarFeature/
  Model/
    Selection/
      PCEventSelectionState.swift                 # State, Stage, NavigationRequest
      PCEventSelectionAction.swift                # Action
      PCEventSelectionReducer.swift               # pure reduce
      PCEventSelectionEffects.swift               # pure effect derivation
      PCEventSelectionManager.swift               # the Store
      PCEventSelectionBindings.swift              # Binding helpers
    PCCalendarModelBuilder.swift                  # unchanged
    PCCalendarMarkerProjector.swift               # extracted from two copies
    SingleCalendarModel.swift                     # slimmed
  View/                                           # unchanged filenames except the rename
  PCEventSelectionEnvironment.swift               # iOS 17 object environment
```

`Packages/DSKit` gets one additive change (§8.2). `Packages/AppNavigation` gets two
(§8.3). `Packages/CalendarListFeature` gets a retype from `CalendarDataSource` to
`PinCalendar` and nothing else.

---

## 5. Value types

All four live in `CoreDomain`, so the data layer can produce them and the feature
layer can consume them without either importing the other.

### 5.1 Date comparison: `PCCalendarDataProvider`, and nothing else

`PCCalendarDataProvider` is the sole owner of `Foundation.Calendar` in the domain
layer, and the reducer carries one in `state.dataProvider` so the transition function
stays pure. It needed one change to be usable that way — `Equatable`:

```swift
public struct PCCalendarDataProvider: Equatable {
    private var calendar: Calendar
    // startOfDay(for:), isSameDay(_:_:), month(of:), year(of:),
    // currentYear, numberOfCurrentMonth, yearData(for:)  — all unchanged
}
```

An earlier draft of this plan proposed a separate `PCDayCalendar` value type for the
same job. That was wrong: `PCDayCalendar` wrapped a second `Calendar` and re-exported
six of the provider's methods, which is a second source of truth wearing the costume
of a fix. The provider already held every one of them. **There is one `Calendar` in
the domain layer and one way to compare days.**

This also retires a live inconsistency. The codebase compares days two ways today —
`PCCalendarDataProvider.isSameDay`, and a bare
`Calendar.autoupdatingCurrent.isDate(_:inSameDayAs:)` in
`AddEditEventBatchListViewModel.eventsForDay`. The latter goes away with that view
model's rewrite in Stage 8.

**Known trap:** `PCCalendarDataProvider.init` overwrites the calendar it is handed —
`self.calendar.timeZone = .current; self.calendar.locale = .current` — so a caller
cannot pin a time zone. Harmless today (every caller passes
`Calendar.autoupdatingCurrent`, whose values are already the current ones), but it
means no test can fix a time zone, and date assertions must be written to hold in
whatever zone they run in. Left alone here because changing it is a behaviour change
to shared code; flagged in §15.

### 5.2 `CalendarEvent`

```swift
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Stable identity for the lifetime of the edit session. Never persisted.
    public let pendingID: UUID
    /// The store-assigned id, once known. `nil` until the batch is written.
    public var persistedID: Int64?

    public var name: String
    public var date: Date
    public var colorName: String

    public var id: UUID { pendingID }
    public var isPersisted: Bool { persistedID != nil }

    public init(
        pendingID: UUID = UUID(),
        persistedID: Int64? = nil,
        name: String = "",
        date: Date,
        colorName: String = ""
    ) { … }

    public func with(name: String) -> CalendarEvent
    public func with(date: Date) -> CalendarEvent
    public func with(colorName: String) -> CalendarEvent
    public func with(pendingID: UUID) -> CalendarEvent
    public func with(persistedID: Int64?) -> CalendarEvent
}
```

Why this shape:

- **`pendingID` is the `Identifiable` id.** Every `ForEach` over batches and events
  is unique by construction. The current code uses `id: Int64` with `0` meaning "not
  saved yet", and `AddEditEventBatchListView` iterates with `id: \.self`; two staged
  batches both carry `id == 0`. A UUID removes that failure mode without a sentinel.
- **No `timestamp`.** It is a session identity that has never been persisted, so it
  becomes `pendingID` and leaves the DTOs entirely (§3.4).
- **No `OrderedSet`.** The invariant is *one event per day*, not *distinct values*.
  An `OrderedSet<CalendarEvent>` would dedupe fully-equal events, which does not enforce
  the day rule, and would silently drop a legitimate event that happened to be
  equal. `events` stays an array sorted by `date`; the day rule lives in
  `BatchAssembly.toggling(day:using:)` (§5.4). No new package dependency.
- **No `dayKey`, and no `PCCalendarDataProvider`.** Two earlier drafts added a
  `dayKey: Date` — `date` normalised to its start-of-day — so the day rule would be a
  dictionary lookup, and threaded a calendar type into the value to derive it. Both
  were wrong. A batch holds a handful of events, so the comparison was never a
  bottleneck; and `dayKey` was a second representation of a fact `date` already
  carried, which had to be recomputed by every setter of `date` and could drift if one
  did not. The rule that stands: **a value never needs a calendar to exist, only to be
  compared.** `CalendarEvent` is constructed from a `Date` and nothing else; the
  calendar appears in `occurs(on:using:)` and `hasSameContent(as:using:)`, which are
  the places that actually ask a question about two dates.

### 5.3 `CalendarEventBatch`

```swift
public struct CalendarEventBatch: Identifiable, Hashable, Sendable {
    public let pendingID: UUID
    public var persistedID: Int64?

    public var name: String
    public var colorName: String
    /// Always sorted ascending by `date`, at most one event per calendar day.
    public var events: [CalendarEvent]

    public var id: UUID { pendingID }
    public var isPersisted: Bool { persistedID != nil }
    public var isEmpty: Bool { events.isEmpty }

    /// Identity for matching an assembly against a committed row. Never a hash.
    public var mergeKey: EventBatchKey {
        persistedID.map(EventBatchKey.persisted) ?? .pending(pendingID)
    }

    /// First event's day, or `nil` when the batch is empty.
    public var date: Date? { events.first?.date }

    public func occurs(on day: Date, using: PCCalendarDataProvider) -> Bool
    public func with(name: String) -> CalendarEventBatch
    public func with(colorName: String, propagateToEvents: Bool) -> CalendarEventBatch
    public func with(events: [CalendarEvent]) -> CalendarEventBatch
    public func with(persistedID: Int64?) -> CalendarEventBatch
    /// Identity-free comparison, used to recognise a staged batch among the rows
    /// that came back from a reload.
    public func hasSameContent(as other: CalendarEventBatch, using: PCCalendarDataProvider) -> Bool
}

public enum EventBatchKey: Hashable, Sendable {
    case persisted(Int64)
    case pending(UUID)
}
```

`date` is **derived**, not stored. Today `AddEditEventBatchViewModel` holds a `date`
that `toggleEvent` never updates when it adds a day, so a batch's own date drifts
away from its events. Deriving it deletes that bug rather than documenting it.

### 5.4 `BatchAssembly`

The unit of work on the line. Pure transformations, no store, no clock.

```swift
public struct BatchAssembly: Equatable {
    public private(set) var batch: CalendarEventBatch
    public private(set) var origin: Origin
    /// Set when a reload revealed this assembly's batch already exists in the
    /// store under a different id, so a later commit updates that row instead of
    /// appending a duplicate.
    public var adoptedPersistedID: Int64?

    public enum Origin: Equatable {
        case new
        case existing(pendingID: UUID)
    }

    public var isNew: Bool { origin == .new }
    public var canSave: Bool {
        !batch.name.isEmpty && !batch.colorName.isEmpty && !batch.events.isEmpty
    }

    // Identity
    public static func new(anchor: Date, colorName: String, using: PCCalendarDataProvider) -> BatchAssembly
    public static func existing(_ batch: CalendarEventBatch) -> BatchAssembly

    // Transformations — each returns a new value
    public func renaming(_ name: String) -> BatchAssembly
    public func recoloring(_ color: PCColorOption?) -> BatchAssembly
    /// Removes any event on `day`, then appends a fresh placeholder, so a day
    /// never holds two events whichever way the toggle goes.
    public func toggling(day: Date, using: PCCalendarDataProvider) -> BatchAssembly
    public func removingEvent(pendingID: UUID) -> BatchAssembly
    /// Replaces by `pendingID`; otherwise, if the incoming event lands on a day
    /// that already has one, replaces that event, so moving an event onto an
    /// occupied day moves it rather than duplicating it. Otherwise appends.
    public func applying(_ event: CalendarEvent, using: PCCalendarDataProvider) -> BatchAssembly
    public func adopting(persistedID: Int64?) -> BatchAssembly
    /// The row to write, or `nil` when the batch has been emptied and must be
    /// removed from the calendar.
    public func resolved(against batches: [CalendarEventBatch]) -> CalendarEventBatch?
}
```

Sorting is applied inside every transformation that can change ordering, so
`events` is sorted by construction and no caller has to remember.

`resolved(against:)` is the single home of the duplicate-batch logic. It replaces
three separate mechanisms: `BatchMergeKey`, `persistedIDsByPendingTimestamp`, and
`contentEquals`.

`recoloring` takes `PCColorOption?`, which lives in `DSKit`, so `BatchAssembly` is
placed in `SingleCalendarFeature`, not `CoreDomain`. Only `CalendarEvent`,
`CalendarEventBatch` and `PinCalendar` are domain types.

---

## 6. The UDF layer

Modelled on the article: a store per feature holding one `State`, mutated only by
`send(_:)`, with a pure `reduce`. `PCEventSelectionManager` is the specialisation
of `Store<State, Action>` — which is why it is also the single communication
channel.

### 6.1 State

```swift
public enum PCEventSelectionStage: Equatable {
    case idle
    case dayList(day: Date)
    case batchEditor
    case eventEditor(batchPendingID: UUID, eventPendingID: UUID)
}

public struct NavigationRequest: Equatable {
    public let id: Int
    public enum Target: Equatable {
        case pushDayList
        case pushBatchEditor
        case pushEventEditor
        case pop
        case popToCalendarRoot
    }
    public let target: Target
}

public struct PCEventSelectionState: Equatable {
    // Assembly line
    public var stage: PCEventSelectionStage = .idle
    public var assembly: BatchAssembly?
    /// The event under edit while `stage == .eventEditor`.
    public var eventDraft: CalendarEvent?
    /// The day the day-list is scoped to, and the anchor the assembly scrolls to.
    public var day: Date?

    // Committed registry — mirror of the persisted calendar
    public var calendarID: Int64 = 0
    public var batches: [CalendarEventBatch] = []

    // Editor calendar
    public var editorYear: Int?
    public var numberOfColumns: Int = 3
    public var scrollAnchor: Date?
    /// Day-marker payload: start-of-day → colour names. The year model is
    /// projected from this after every action, in place.
    public var dayEventColors: [Date: [String]] = [:]

    // Main-calendar multi-select session
    public var multiSelectMode = false
    public var multiSelectDays: [Date] = []
    public var multiSelectColor: PCColorOption?

    // Environment the reducer needs (§5.1)
    public var dataProvider = PCCalendarDataProvider()

    // Intent
    public var isDirty = false
    public var didSave = false
    public var navigationRequest: NavigationRequest?

    // MARK: - Derivations
    public var dayBatches: [CalendarEventBatch] {
        guard let day else { return [] }
        return batches
            .filter { $0.occurs(on: day, using: dataProvider) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
    public var canSave: Bool { assembly?.canSave ?? false }
}
```

`PCCalendarYearModel` is a `@MainActor` class and cannot live in a value state. It
stays a property of the store and is **projected** from `state` after each action
(§7.3). Stated rather than hidden: the state is a pure value, the calendar is a
render target derived from it.

### 6.2 Action

```swift
public enum PCEventSelectionAction: Equatable {
    // Entry
    case ensureAssemblyStarted
    case dayTappedInCalendar(Date)
    case startNewBatch(on: Date)
    case openBatch(pendingID: UUID)
    case confirmMultiSelectTapped

    // Stage transitions
    case backTapped
    case closeTapped
    case cancelTapped
    case navigationRequestHandled

    // Batch editor
    case setBatchName(String)
    case setBatchColor(PCColorOption?)
    case toggleDay(Date)
    case removeEvent(pendingID: UUID)

    // Event editor
    case openEvent(pendingID: UUID)
    case setEventName(String)
    case setEventDate(Date)
    case setEventColor(PCColorOption?)

    // Persistence
    case commitTapped
    case saveTapped
    case saveEventTapped
    case discardEventTapped
    case deleteBatches([CalendarEventBatch])

    // Main calendar
    case setMultiSelectMode(Bool)
    case setMultiSelectColor(PCColorOption?)
    case cancelMultiSelectTapped
    case setNumberOfColumns(Int)
    case setEditorYear(Int)
    case setScrollAnchor(Date?)

    // External sync
    case syncCalendar(calendarID: Int64, batches: [CalendarEventBatch])
    case resetSession
}
```

### 6.3 Reducer

A free function. No `self`, no clock, no I/O.

```swift
public let pcEventSelectionReducer: (PCEventSelectionState, PCEventSelectionAction) -> PCEventSelectionState
```

#### Entry

| Action | Guard | State change | Navigation |
|---|---|---|---|
| `ensureAssemblyStarted` | `assembly == nil`, `stage == .idle` | no change | none — idempotent no-op when the state already has an assembly |
| `dayTappedInCalendar(d)` | `multiSelectMode` | `multiSelectDays` gains/loses `d`; `dayEventColors` updated for `d` | — |
| `dayTappedInCalendar(d)` | `!multiSelectMode`, day has no batches | `day = d`; `assembly = .new(anchor: d, …)`; `stage = .batchEditor`; `scrollAnchor = d`; `editorYear = nil`; `isDirty = true` | `pushBatchEditor` |
| `dayTappedInCalendar(d)` | `!multiSelectMode`, day has batches | `day = d`; `stage = .dayList(day: d)`; `assembly = nil` | `pushDayList` |
| `startNewBatch(on: d)` | — | `day = d`; `assembly = .new(anchor: d, …)`; `stage = .batchEditor`; `scrollAnchor = d`; `isDirty = true` | `pushBatchEditor` |
| `openBatch(pendingID:)` | batch found in `batches` | `day = batch.date`; `assembly = .existing(batch)`; `stage = .batchEditor`; `scrollAnchor = batch.date`; `editorYear = nil`; `isDirty = true` | `pushBatchEditor` |
| `confirmMultiSelectTapped` | `multiSelectDays` non-empty | `assembly = .new(all: multiSelectDays, color: multiSelectColor)`; `stage = .batchEditor`; multi-select reset; `isDirty = true` | `pushBatchEditor` |

#### Stage transitions

| Action | Guard | State change | Navigation |
|---|---|---|---|
| `backTapped` | `stage == .eventEditor` | `eventDraft = nil`; `stage = .batchEditor` | `pop` |
| `backTapped` | `stage == .batchEditor` | `stage = .dayList(day)` if `day != nil` else `.idle`; `assembly = nil` when leaving the line | `pop` |
| `backTapped` | `stage == .dayList` | `stage = .idle`; `day = nil`; `assembly = nil` | `pop` |
| `closeTapped` | — | `stage = .idle`; `day = nil`; `assembly = nil`; `eventDraft = nil`; `isDirty = false`; `dayEventColors` rebuilt from `batches` | `popToCalendarRoot` |
| `cancelTapped` | — | as `closeTapped` | `popToCalendarRoot` |
| `navigationRequestHandled` | — | `navigationRequest = nil` | — |

#### Batch editor

| Action | Guard | State change |
|---|---|---|
| `setBatchName(n)` | `assembly != nil` | `assembly = assembly.renaming(n)`; `isDirty = true` |
| `setBatchColor(c)` | `assembly != nil` | `assembly = assembly.recoloring(c)`; `dayEventColors` updated; `isDirty = true` |
| `toggleDay(d)` | `stage == .batchEditor`, `assembly != nil` | `assembly = assembly.toggling(day: d, days:)`; `dayEventColors` updated; `isDirty = true` |
| `removeEvent(pendingID:)` | `assembly != nil` | `assembly = assembly.removingEvent(pendingID:)`; `dayEventColors` updated; `isDirty = true` |

#### Event editor

| Action | Guard | State change | Navigation |
|---|---|---|---|
| `openEvent(pendingID:)` | event found in `assembly.batch.events` | `eventDraft = event`; `stage = .eventEditor(batchPendingID:, eventPendingID:)` | `pushEventEditor` |
| `setEventName(n)` | `eventDraft != nil` | `eventDraft = eventDraft.with(name: n)`; `isDirty = true` | — |
| `setEventDate(d)` | `eventDraft != nil` | `eventDraft = eventDraft.with(date: d)`; `isDirty = true` | — |
| `setEventColor(c)` | `eventDraft != nil` | `eventDraft = eventDraft.with(colorName: c?.colorName ?? "")`; `isDirty = true` | — |
| `saveEventTapped` | `eventDraft != nil`, name non-empty | `assembly = assembly.applying(eventDraft!, days:)`; `eventDraft = nil`; `stage = .batchEditor`; `dayEventColors` updated; `isDirty = true` | `pop` |
| `discardEventTapped` | — | `eventDraft = nil`; `stage = .batchEditor` | `pop` |

#### Persistence

| Action | Guard | State change | Navigation |
|---|---|---|---|
| `commitTapped` | `assembly != nil`, `canSave` | assembly merged into `batches` by `mergeKey`; `isDirty = true` | — |
| `saveTapped` | `stage == .dayList` | `stage = .idle`; `day = nil` | `popToCalendarRoot` |
| `saveTapped` | `stage == .batchEditor`, `canSave`, resolved batch non-empty | merged into `batches`; `assembly = nil`; `stage = .dayList(day)`; `didSave = true`; `isDirty = false` | `pop` |
| `saveTapped` | `stage == .batchEditor`, resolved batch `nil` | assembly's row removed from `batches` by `mergeKey`; `assembly = nil`; `stage = .idle`; `didSave = true`; `isDirty = false` | `popToCalendarRoot` |
| `saveTapped` | `stage == .eventEditor`, `canSave` | draft applied to assembly, assembly merged into `batches`; `eventDraft = nil`; `assembly = nil`; `stage = .dayList(day)`; `didSave = true` | `pop` |
| `deleteBatches(list)` | — | rows removed from `batches` by `mergeKey`; `isDirty = true`; `dayEventColors` rebuilt | `popToCalendarRoot` when `dayBatches` empties, else none |
| `syncCalendar(id, incoming)` | `id == calendarID` | staged assembly adopted against `incoming` (§6.5); `batches = incoming`; `calendarID = id`; `isDirty = false` | — |
| `resetSession` | — | `= .init(dataProvider: dataProvider)` | — |

#### Main calendar and misc

| Action | Guard | State change |
|---|---|---|
| `setMultiSelectMode(on)` | — | `multiSelectMode = on`; on `false`, also clears days and colour |
| `setMultiSelectColor(c)` | — | `multiSelectColor = c` |
| `cancelMultiSelectTapped` | — | `multiSelectDays = []`; `multiSelectColor = nil`; `dayEventColors` rebuilt |
| `setNumberOfColumns(n)` | — | `numberOfColumns = n`; `isDirty = true` |
| `setEditorYear(y)` | — | `editorYear = y` |
| `setScrollAnchor(d)` | — | `scrollAnchor = d` |

Every action has at least one row. There is no fall-through case, and no failed guard
returns `.idle` — a rejected action leaves the state untouched, which is what stops a
stray action from destroying committed work.

### 6.4 Effects

A second pure function, and the answer to "how does a *pure* reducer trigger a
write?" — it does not. The effect derivation reads the post-action state and says
what should happen; only the store executes it.

```swift
public enum PCEventSelectionEffect: Equatable {
    case writeCalendar(calendarID: Int64, numberOfColumns: Int, batches: [CalendarEventBatch])
}

public let pcEventSelectionEffects:
    (PCEventSelectionAction, PCEventSelectionState, PCEventSelectionState) -> [PCEventSelectionEffect]
```

| Action | Effect |
|---|---|
| `commitTapped` | `writeCalendar` when the merge changed `batches` |
| `saveTapped` | `writeCalendar` |
| `saveEventTapped` | none — an event save does not commit the batch |
| `deleteBatches` | `writeCalendar` |
| `setNumberOfColumns` | `writeCalendar` with the current batches |
| `setBatchColor` / `toggleDay` / `removeEvent` / `setEventDate` / `setEventName` / `setBatchName` | none — staged only |
| `syncCalendar` | `writeCalendar` **only** when an adoption reassigned a `persistedID` |
| everything else | none |

Effects carry `CalendarEventBatch`, never DTOs. The mapping happens in the data layer
(§3.4), one call away.

### 6.5 Reload adoption

The reported duplicate-batch bug: a batch committed with `persistedID == nil` comes
back from the store with a real id, so a later commit keyed on the pending UUID finds
nothing and appends a second row. In `syncCalendar`:

1. If `assembly` is `.new` and not yet adopted, look for a row in `incoming` with
   `persistedID != nil` and `hasSameContent(as: assembly.batch, days:)` whose
   `pendingID` is not already claimed in the registry. If found, set
   `assembly.adoptedPersistedID = thatRow.persistedID`.
2. `batches = incoming`, each row keeping the `pendingID` it had, so a staged row
   that came back under a new id is still matchable.
3. If an adoption happened, emit `writeCalendar` once so the reassignment lands.

This is the whole of the old `persistedIDsByPendingTimestamp` + `contentEquals` pair,
expressed once, in a pure function, and testable.

---

## 7. The store

### 7.1 Type

```swift
@MainActor
@Observable
public final class PCEventSelectionManager {
    public private(set) var state: PCEventSelectionState
    /// The batch editor's calendar. A render target projected from `state`; see
    /// §6.1 for why it is not part of the state.
    public private(set) var yearModel: PCCalendarYearModel

    private let persistence: any CalendarPersisting
    private let columnCountResolver: (Int) -> Int
    private let dataProvider: PCCalendarDataProvider
    private var writeChain: Task<Void, Never>?

    public init(
        initialState: PCEventSelectionState = .init(),
        persistence: any CalendarPersisting,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        columnCountResolver: @escaping (Int) -> Int = { $0 }
    ) { … }

    public func send(_ action: PCEventSelectionAction)
}
```

`import` list for this file: `Foundation`, `Observation`, `CoreDomain`, `DSKit`.
Not `CorePersistence` — the dependency is the `CalendarPersisting` port, and the
concrete `CalendarCache` is named only in `PCCalendarSession`.

`columnCountResolver` and `numberOfColumns` are preserved because they carry the
`-UITestColumns` launch-argument override the UI suite depends on. Losing them breaks
every UI test that relies on large tap targets.

`dataProvider` is retained for one job: building the year matrix through
`PCCalendarModelBuilder`. The reducer never consults it.

### 7.2 `send`

```swift
public func send(_ action: PCEventSelectionAction) {
    let previous = state
    let next = pcEventSelectionReducer(previous, action)
    if next != previous { state = next }
    projectCalendar()
    let effects = pcEventSelectionEffects(action, previous, next)
    guard !effects.isEmpty else { return }
    for effect in effects { perform(effect) }
}
```

No `didSet`, no property observers on the `@Observable` property — reconciliation
happens in `send`, where it is explicit.

### 7.3 Projection and persistence

```swift
private func projectCalendar() {
    // Rebuild the matrix only when the year or column count changed; otherwise
    // mutate `day.events` in place. PCCalendarYearModel.months documents that the
    // views bind to these day-model instances, so a per-action rebuild would stop
    // observation.
    if yearModel.months.isEmpty
        || yearModel.year != (state.editorYear ?? dataProvider.currentYear)
        || yearModel.numberOfColumns != resolvedColumns {
        yearModel = PCCalendarModelBuilder.makeYearModel(…)
    }
    PCCalendarMarkerProjector.apply(state.dayEventColors, to: yearModel, using: state.dataProvider)
    yearModel.scrollTargetMonth = state.scrollAnchor.map { state.dataProvider.month(of: $0) }
}

private func perform(_ effect: PCEventSelectionEffect) {
    guard case .writeCalendar(let id, let columns, let batches) = effect, id != 0
    else { return }
    let previous = writeChain
    // Serialised: a write begins only after the one before it finished, and always
    // reflects the latest state. Two concurrent writers were the cause of silently
    // dropped calendar updates.
    writeChain = Task { [persistence] in
        await previous?.value
        try? await persistence.save(numberOfColumns: columns, eventBatches: batches, forCalendar: id)
    }
}
```

`writeChain` replaces the two uncoordinated `Task`s in
`PCEventsSelectionManager.persistBatches` and `SingleCalendarModel.save(for:)`,
which both read-modify-write the same `PPCalendar`. It also makes the 350 ms debounce
in `SingleCalendarView` unnecessary: trailing writes coalesce naturally, so the
`Task.sleep` and its `onDisappear` flush are deleted.

---

## 8. Wiring

### 8.1 `SingleCalendarFeature`

**Marker projector.** Extracted once, used by the store and by `SingleCalendarModel`
for the main calendar:

```swift
@MainActor
enum PCCalendarMarkerProjector {
    static func apply(
        _ colorsByDay: [Date: [String]],
        to yearModel: PCCalendarYearModel,
        using: PCCalendarDataProvider
    )
    static func colorsByDay(from batches: [CalendarEventBatch], using: PCCalendarDataProvider) -> [Date: [String]]
}
```

This deletes the two near-identical copies in
`PCEventsSelectionManager.updateYearModel`/`eventColorsByDay` and
`SingleCalendarModel.updateYearModel`/`colorsByStartOfDay`, plus the linear day scan
in `SingleCalendarModel.dayModel(for:)` that existed only for a single-day fast path.

**Environment.** iOS 17 observable objects in the environment, so no wrapper is
needed. One line at the app root:

```swift
// PinCalAppApp
.environment(session)
.environment(session.eventSelection)   // the PCEventSelectionManager
.environment(\.calendarCache, session.cache)
```

Views read it with `@Environment(PCEventSelectionManager.self) private var store`.
`PCCalendarSession` remains the composition root, and is the only file in the app
that names both `CalendarCache` and `PCEventSelectionManager`. Its field
`eventsSelectionManager` is renamed `eventSelection`.

**View models survive as stateless projection facades.** Requirement 2's companion
decision: views keep talking to a view model, and the view model talks to the
assembler. Nothing in a view constructs or reads the store.

The rule that makes this work rather than reproduce the current dual-source problem:

> A view model may hold **view-scoped** state. It may never hold **domain** state.

| Allowed in a view model | Forbidden in a view model |
|---|---|
| List edit mode and delete staging (`isEditing`, `eventBatchesToDelete`) | `events`, `batches`, a stored copy of either |
| Focus, expansion flags, transient animation state | `eventBatchId`, `eventBatchName`, `date`, `timestamp` |
| Derived title/format strings | `selectedColor`, `event: CalendarEvent`, `eventId` |
| A reference to the assembler | Any stored copy of anything the reducer owns |

Today all four view models break this rule: `AddEditEventBatchViewModel` holds
`eventBatchId`/`eventBatchName`/`date`/`timestamp`/`eventBatch`; `AddEditEventBatchListViewModel`
holds a stored `eventBatches` copy; `AddEditEventViewModel` holds its own
`event: EventDataSource`. Collapsing those into `state` is what removes the four
copies of "pending batch state" the plan is for.

**Shape: a plain struct, not `@Observable`.**

```swift
@MainActor
public struct AddEditEventBatchViewModel {
    let assembler: PCEventSelectionManager

    init(assembler: PCEventSelectionManager) { self.assembler = assembler }

    // Projection — read by the view, never stored
    var batchName: String { assembler.state.assembly?.batch.name ?? "" }
    var canSave: Bool { assembler.state.canSave }
    var events: [CalendarEvent] { assembler.state.assembly?.batch.events ?? [] }
    var preferredTitle: String? { … }
    var compactTitle: String? { … }

    // Two-way controls
    var nameBinding: Binding<String> {
        Binding(get: { batchName }, set: { assembler.send(.setBatchName($0)) })
    }
    var colorBinding: Binding<PCColorOption?> {
        Binding(get: { assembler.state.assembly?.batch.colorName.flatMap(PCColorOption.init) },
                set: { assembler.send(.setBatchColor($0)) })
    }

    // Commands — the only way a view model changes anything
    func save() { assembler.send(.saveTapped) }
    func commit() { assembler.send(.commitTapped) }
    func toggle(_ day: Date) { assembler.send(.toggleDay(day)) }
    func remove(_ event: CalendarEvent) { assembler.send(.removeEvent(pendingID: event.pendingID)) }
    func open(_ event: CalendarEvent) { assembler.send(.openEvent(pendingID: event.pendingID)) }
}
```

Making the view models non-`@Observable` structs is deliberate and it is what removes
an observation hazard rather than adding one. The assembler is the *only*
`@Observable` object in the graph. A view reads `viewModel.canSave`, which calls
`assembler.state.canSave` during body evaluation, so the `@Observable` registrar
records the read on `state` and any `send` invalidates the view. There is no second
observation registration to keep in sync, and no stored copy that can go stale.

This is also why the VMs become cheap to construct: they hold one reference, so a
view builds one inline per render instead of storing it in `@State`.

```swift
public struct AddEditEventBatchScreen: View {
    @Environment(PCEventSelectionManager.self) private var assembler
    public let calendarID: Int64

    public var body: some View {
        AddEditEventBatchView(
            viewModel: AddEditEventBatchViewModel(assembler: assembler),
            calendarID: calendarID
        )
        .task { assembler.send(.ensureAssemblyStarted) }
    }
}
```

The one place a view model still needs its own storage is
`AddEditEventBatchListViewModel`, because list edit mode and delete confirmation are
genuinely view-scoped and not part of the batch domain:

```swift
@MainActor @Observable
public final class AddEditEventBatchListViewModel {
    private let assembler: PCEventSelectionManager

    // View-scoped only — permitted by the rule above
    var isEditing = false
    var pendingDeletion: [CalendarEventBatch] = []
    var confirmation: ConfirmationDialogState?

    // Projected — never stored
    var eventBatches: [CalendarEventBatch] { assembler.state.dayBatches }
    var selectedDay: Date? { assembler.state.day }

    func remove(_ batch: CalendarEventBatch) { pendingDeletion = [batch] }
    func confirmDelete() {
        assembler.send(.deleteBatches(pendingDeletion))
        pendingDeletion = []
    }
    func cancel() { pendingDeletion = []; isEditing = false }
}
```

`eventBatches` is a **computed** property, never a stored copy. The current
implementation stores a copy and re-primes it in `onAppear` and
`onChange(of: eventBatchesToDelete)`, precisely because a computed version was found
not to refresh. That work-around exists only to compensate for holding a duplicate;
once the reducer owns the only copy, the computed property is correct and the
re-priming calls disappear. §12.5 pins this with a regression test so it cannot
regress silently.

**View signatures.** Views keep taking a view model, as today. Only the manager
parameter becomes the environment lookup:

| View | Before | After |
|---|---|---|
| `AddEditEventBatchScreen` | `(eventsSelectionManager:calendarId:source:eventBatch:)` | `(calendarID: Int64)` |
| `AddEditEventBatchListView` | `(eventsSelectionManager:daySelectionManager:calendarId:selectedDay:)` | `(calendarID: Int64)` |
| `AddEditEventView` | `(eventsSelectionManager:source:)` | `()` |
| `AddEditEventListView` | `(manager:)` | `()` |

**Navigation fulfilment.** `state.navigationRequest` is read by the *view model's
host view*, which is the one object that already holds `RootNavigation`:

```swift
.onChange(of: viewModel.navigationRequest) {
    navigation.goTo($0.target.route)
    viewModel.didFulfilNavigationRequest()
}
```

where `route` maps the target onto an `AppRoute`. The mapping is the only place a
navigation request becomes a route, so the view models stay free of `AppNavigation`
except for that one file.

**Entry is dispatched, never initialised.** No view `init` and no
`@State(initialValue:)` may send an action, and no view model may mutate the assembler
from `init`. Entry happens from `.task`/`.onAppear` of the **visible** screen only,
once, guarded. Speculative `navigationDestination` construction runs view `init`s for
screens the user has not reached; if entry ran there it would commit phantom batches
and steal day markers onto year models that are not on screen. This is the single
most valuable invariant in the plan, which is why it is called out in §10.

### 8.2 `DSKit` (additive)

`PCCalendarDaySelectionManager` gains one callback:

```swift
public var onDayTapped: ((Date) -> Void)?

public func select(day: PCCalendarDayModel) {
    guard day.isInCurrentMonth, let date = day.date else { return }
    switch selectionMode { … }               // unchanged
    onDayTapped?(date)
}
```

This is the whole DSKit change, and it is the one that matters most. `selectedDays`
is today a mutable message bus: `AddEditEventBatchScreen` observes it with `onChange`
and calls `toggleEvent`, while `SingleCalendarView` observes the same set and routes
navigation. Two observers on one set is why seeding
`selectedDays = Set(batch.events.map(\.date))` on open would silently toggle a real
event off, and why `prepare(with:)` has to defensively clear it. A direct tap callback
has no such failure mode, and `selectedDays` becomes purely presentational.

`PCColorOption` gains explicit `: Equatable, Hashable` so it can sit in state.

### 8.3 `AppNavigation` (additive)

`AppRoute`'s three push cases lose their payloads, because the payload now lives in
the store:

```swift
case dayBatches          // was dayBatches(Date)
case batchEditor         // was batchEditor(BatchEditorSource)
case eventEditor         // was eventEditor(EventEditorSource)
```

`BatchEditorSource` and `EventEditorSource` are deleted. `RootNavigation` gains:

```swift
public func pop() { if !path.isEmpty { path.removeLast() } }
```

`navigationStyle` is unchanged (`.push` for all three), so `goTo` needs no new arm.
`RootNavigationTests` needs the `batchEditor`/`dayBatches` assertions at lines
184-192 updated, four cases removed, and a new `pop` case added.

### 8.4 `CorePersistence` and `CalendarListFeature`

`CalendarCache` conforms to `CalendarPersisting`:

```swift
public actor CalendarCache: CalendarPersisting {
    public func calendar(id: Int64) async throws -> PinCalendar? { … }
    public func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws { … }
}
```

`calendar(id:)` and `eventBatches(calendarID:)` split what `getCalendar(id:)` used to
return in one object. `save` keeps the current re-fetch-and-publish behaviour so
store-assigned ids flow back to observers. `updateCalendar`, `archiveCalendar`,
`restoreCalendar`, `permanentlyDeleteCalendar`, `createCalendar`, `loadActive`,
`loadArchived`, `getAllCalendars` and `changes` retype `CalendarDataSource` →
`PinCalendar`; `EventBatchDataSource` → `CalendarEventBatch` and `EventDataSource` →
`CalendarEvent` stay internal to the module. `CalendarListFeature`'s
`CalendarListViewModel` and `AddEditCalendarViewModel` retype to `PinCalendar`, and
`CalendarCacheIntegrationTests` follows. No behaviour change in either module — the
calendar list only ever read the five scalars `PinCalendar` carries.

---

## 9. What `SingleCalendarModel` keeps

| Kept | Removed — now store state or actions |
|---|---|
| `calendarid`, `label`, `isArchived`, `state` | `originalBatches` (proxied to the manager) |
| `yearModel` (the **main** panel) | `addedEvents`, `selectedColor` |
| `fetch(force:)`, `switchYear(to:)` | `route(for:)`, `handleSelectionConfirmation()` |
| `daySelectionManager` | `prepareNewBatchEvents`, `prepareAddEditEventBatchViewModel` |
| `columnCountResolver` | `makeBatchEditor()`, `changeEvent(_:)` |
| `columnCountSaveTask` → deleted | `commitPendingBatch`, `cancelMultipleChanges` |
| | `batches(for:)`, `batch(withId:)`, `batch(for:)` |
| | `deleteBatches(_:for:)`, `save(for:)` |
| | `onBatchListDismissed`, `resetSelectedDays`, `reset` |
| | `updateYearModel`, `updateDayModel`, `dayModel(for:)`, `colorsByStartOfDay` |

`fetch` maps the persisted calendar and sends one action:

```swift
let batches = try await persistence.eventBatches(calendarID: calendarid)
eventSelection.send(.syncCalendar(calendarID: calendarid, batches: batches))
```

The main calendar's markers are projected with
`PCCalendarMarkerProjector.colorsByDay(from: state.batches, days:)`, so both panels
read the same committed registry through the same code.

`SingleCalendarModel` keeps its Combine subscription to `CalendarCache.changes` for
calendar metadata (`label`, `year`, `isArchived`, column count). It is the calendar's
own metadata, not batch state, and the manager is the only writer and the only owner
of batches. §13 records why the alternative was rejected.

Two independent `PCCalendarYearModel` trees remain: the main calendar and the editor
each navigate years independently, and the UI tests target the editor's calendar by
its `batch-editor-calendar` identifier. What is removed is the duplicated *logic* —
construction through one builder, markers through one projector.

---

## 10. Invariants

Each is checkable, and each maps to a test in §12.

1. **One writer.** `CalendarPersisting.save` for this calendar is called from exactly
   one place, `PCEventSelectionManager.perform`. No other type holds the write path.
2. **Writes are serialised.** A write begins only after the previous one finished.
3. **No DTO above the data edge.** `EventDataSource`, `EventBatchDataSource`,
   `CalendarDataSource` and every `PP*` entity are internal to `CorePersistence`. No
   file in `SingleCalendarFeature/Model/` or `/View/` imports `CorePersistence`.
4. **No `hashValue` in identity.** A batch is identified by `persistedID ?? pendingID`,
   both stable for the batch's lifetime.
5. **Unique view identity.** `CalendarEvent` and `CalendarEventBatch` are `Identifiable` by
   `pendingID`. No `0` sentinel reaches a `ForEach`.
6. **Events are date-sorted and day-unique.** Enforced in `BatchAssembly`, asserted
   after every transformation.
7. **`CalendarEventBatch.date` is derived.** Nothing stores it, so it cannot drift.
8. **No entry from `init`.** Actions are dispatched from `.task`/`.onAppear` of
   visible screens, once, guarded.
9. **The reducer is pure.** No clock, no I/O, no service lookup. Persistence comes
   only from the effect derivation.
10. **The day tap has exactly one listener at a time.** `onDayTapped` is installed by
    the visible screen and cleared on disappear. No screen observes `selectedDays` to
    decide what a tap means.
11. **Stage is the only navigation input.** A view never decides to push; it reads
    `state.stage` and `state.navigationRequest`.
12. **View models hold no domain state.** A view model may hold view-scoped state
    (list edit mode, pending deletion, focus) and a reference to the assembler, and
    nothing else. Every domain value is read from `assembler.state` through a computed
    property and changed only by `send`.
13. **The assembler is the only `@Observable` object in the batch flow.** View models
    are plain structs, except `AddEditEventBatchListViewModel`, which is `@Observable`
    for its own view-scoped state only and projects everything else.
14. **No ObjectBox schema change.** `PPCalendar`, `PPEventBatch`, `PPEvent` and the
    generated `EntityInfo` are untouched by this refactor, so no store migration and
    no codegen re-run.

---

## 11. Stages

Each stage ends with the suite at or above the `TEST_BASELINE.md` numbers and is one
branch, `feature/batch-assembly/stage-N`. The order guarantees the project builds and
tests green at every stage, which the previous revision of this plan did not.

| Stage | Work | Green gate |
|---:|---|---|
| **0** | **Baseline.** Record the full suite including UI tests. | **Done** — see `TEST_BASELINE.md`: 229 unit, 29 UI, 0 failures |
| 1 | **Rename** `AddEditListView` → `AddEditEventListView` and its model (requirement 1). Add `typealias` shims. Update `AddEditEventBatchView`, previews, `AddEditListViewModelTests`. | 229 / 29 |
| 2 | **`CoreDomain`.** Add `PinCalendar`, `CalendarEventBatch`, `CalendarEvent`, `CalendarPersisting`; make `PCCalendarDataProvider` `Equatable` so it can live in state. No behaviour change. | 247 unit |
| 3 | **Composition-root mapping + additive fixes.** `EntityMappable`, `RootMapper` and `CalendarStore` added to `PinCalApp/Root/`, with their 22 tests in `PinCalAppTests` (which gains `CorePersistence` + `CoreDomain` package dependencies). `PinCalAppApp` assembles everything and owns the cache; `PCCalendarSession` exposes `persistence` only — no `cache` — and builds nothing. `CorePersistence` gains **no** dependency on `CoreDomain` and no new file — untouched apart from the dead assignment. **ObjectBox schema untouched.** | 268 unit |
| 4a | **Combine → `AsyncStream`.** `CalendarCache` replaces `PassthroughSubject` with a continuation fan-out and loses `import Combine`; `SingleCalendarModel` and `CalendarListViewModel` consume `for await` in a `Task`; the 5 sinks in `CalendarCacheIntegrationTests` become awaited collectors. `CalendarCache.loadedCalendars()` is added so a first paint reads its own result instead of awaiting the broadcast it triggered. Combine leaves the app. | 269 unit, 7 UI |
| 4b | **`CalendarListFeature` onto `PinCalendar`.** Nothing moves: the package stays at `Packages/CalendarListFeature`. Four files switch `CalendarDataSource` → `PinCalendar` (five scalars; the list never read the event graph), `ChangeOperation` follows, and `Package.swift` gains `CoreDomain` while **keeping** `CorePersistence`. `PCCalendarSession` gains `eventSelection`. | 229 / 29 |
| 5 | **`SingleCalendarFeature` UDF types.** `PCEventSelectionState`/`Stage`/`NavigationRequest`, `Action`, the reducer and the effect derivation, plus `PCCalendarMarkerProjector`. No caller wired yet. | 229 / 29, plus the new reducer suites |
| 6 | **The store.** `PCEventSelectionManager` beside the old manager: `send`, projection, `perform`, `writeChain`; injected via `.environment`. `AppNavigation`: `pop()`, payload-free push routes, `BatchEditorSource`/`EventEditorSource` deleted. | 229 / 29, plus store suites |
| 7 | **`DSKit`.** `onDayTapped` on `PCCalendarDaySelectionManager`; `Equatable`/`Hashable` on `PCColorOption`. Stop every screen observing `selectedDays`; dispatch from `onDayTapped` instead. | 229 / 29 |
| 8 | **Thread the assembler through the view models.** Keep all four view models and rebuild each as a projection facade over `PCEventSelectionManager`: no stored domain state, computed projections, commands that `send`. `AddEditEventListView` takes `AddEditEventListViewModel(assembler:)`. Delete the `typealias` shims. | 29 UI, incl. `BatchEditCommitTests` |
| 9 | **Slim `SingleCalendarModel`** to §9. Route `fetch` through `syncCalendar`. Remove `save(for:)`, `commitPendingBatch`, `deleteBatches`, `route(for:)`, `updateYearModel`, `dayModel(for:)`, `colorsByStartOfDay`, the `addedEvents` staging and the 350 ms debounce. | 29 UI |
| 10 | **Delete the leftovers.** The `onEventsChanged` / `onEventApplied` closures, `columnCountSaveTask`, and `PCEventsSelectionManager` itself. | 229 / 29 |
| 11 | **Close out the UI suite.** New multi-day scenario: tap two days, save, assert one batch with two days. | 29 + 1 UI |
| 12 | **The bug in §16**, once 4b–11 are green. Not before — the refactor replaces the machinery it lives in. | §16.4 |

### 11.1.1 The rule Stage 4a established

`AsyncStream` is an **async sequence you await**, not a channel you subscribe to. One
rule came out of it, and it is the reason the stage needed a second pass:

> **A push stream has no replay. A consumer must never await an event it triggered
> itself — it should read the result.**

`CalendarListViewModel.fetch` used to call `loadActive()` and wait for the `.refresh`
broadcast that call emitted. That worked with Combine, which registered synchronously
inside `.sink`. `AsyncStream` registers when the consuming `Task` runs, so the
broadcast could land first: six tests in `CalendarListFeatureTests` failed, one of them
by indexing an empty array. The fix is `loadActive()` then `loadedCalendars()` — read
what you asked for, do not wait for the echo.

`SingleCalendarModel` already did this, which is why it was unaffected.

The other properties worth stating, because they are what make `AsyncStream` the wrong
tool when misused: it is **single-consumer** (a second `for await` is undefined, so a
fan-out is yours to build), it **buffers unbounded** by default (a slow consumer is a
leak, not backpressure), and its **delivery is serialised per consumer**.

### 11.2 When the DTOs actually close

The access modifiers on the three `*DataSource` structs cannot be tightened until their
last consumer is gone, and each has a different one. This is why Stage 3 is additive
only:

| DTO | Last consumer | Becomes `internal` in |
|---|---|---|
| `CalendarDataSource` | `CalendarListFeature` **and** `SingleCalendarModelTests`, whose `InMemoryCalendarRepository: CalendarRepository` fake is built on it and uses a plain import | **Stage 9** |
| `EventDataSource`, `EventBatchDataSource` | `PCEventsSelectionManager` and the four view models | **Stage 9** |

Doing it earlier breaks the build, and doing it all at once means one enormous commit
spanning two packages. So for the middle of the sequence the boundary is deliberately
half-open — two of the three are closed from Stage 4, and all three from Stage 9. The
invariant in §10.3 is therefore a Stage 9 assertion, not a Stage 3 one.

The same applies to `EventDataSource.timestamp`. `pendingID` replaces it, but
`PCEventsSelectionManager` still keys on `timestamp` in three places
(`key(for:)`, `apply(_:)` and `persistedIDsByPendingTimestamp`) and
`AppNavigation.EventEditorSource` still carries it. Both go in Stages 6 and 8.

Stage 8 before Stage 9 is deliberate: the view models are what stand between the
views and the assembler, so rebuilding them first makes the `SingleCalendarModel`
slimming a mechanical follow-through rather than one combined diff. Stage 3 before
Stage 4 is deliberate because `CalendarListFeature` cannot be retargeted until the
data layer actually produces `PinCalendar`.

### 11.1 Per-stage test routine

Wall-clock figures measured from `TEST_BASELINE.md`, so each stage's gate is a known
duration rather than an open-ended suite.

| Gate | What runs | Wall clock | When |
|---|---|---:|---|
| **Inner loop** | `SingleCalendarFeatureTests` (132) | ~35 s | while writing a stage |
| **Inner loop** | `BatchEditCommitTests` (7) | ~267 s | while writing stages 6-9, which touch the batch UI |
| **Stage end** | the two unit batches | ~90 s | before opening the PR |
| **Stage end** | `BatchEditCommitTests` (7) | ~267 s | before opening the PR |
| **Stage end** | remaining UI (22) | ~578 s | stages touching views, and every 3rd stage otherwise |
| **Full** | everything | ~15.6 min | at Stage 0, Stage 8, Stage 9, Stage 11 |

The remaining 22 UI tests are `KeyboardAvoidance*`, `EditorKeyboardAvoidance*`,
`PerfScrollTests`, `PinCalAppUITests` and `PinCalAppUITestsLaunchTests`. They are
unaffected by stages 1-7 (renames, additions, data-layer retype, DSKit callback), so
they run at stage end rather than on every iteration. Skipping them on a stage that
touches no view is the single biggest time saving available: 578 s of the 936 s
total.

---

## 12. Test plan

Every stage is held to `TEST_BASELINE.md`. Nothing below replaces a baseline suite; it
adds to it.

### 12.1 Reducer, pure

One test per row of the §6.3 and §6.4 tables. Plus:

- every `PCEventSelectionAction` case appears in at least one test, enforced by
  iterating an `allActions` list and asserting each either changes state or emits an
  effect, so a newly added action cannot ship unhandled;
- a rejected action leaves state byte-identical — in particular `setBatchName` with
  no assembly, and `openEvent` with an unknown id;
- `toggleDay` twice on the same day returns the original event count;
- applying an event onto an occupied day moves it rather than duplicating it.

### 12.2 Assembly and value types

- `BatchAssembly`: `.new(anchor:)` seeds exactly one event; `toggling` both ways;
  `resolved(against:)` returns `nil` when emptied; `resolved` reuses the row matched
  by `mergeKey`; `canSave` requires name, colour and a non-empty event list.
- `CalendarEventBatch.hasSameContent` ignores identity, compares name, colour and day set.
- `DomainMapping` round-trips: a persisted id survives; `nil` `persistedID` maps to DTO
  id `0`; a staged batch never gains an id; the DTO `timestamp` is never read.

### 12.3 Store

- `syncCalendar` adoption: a staged batch returns under a real id; the next
  `saveTapped` updates that row rather than appending. **This is the regression test
  for the reported duplicate bug**, replacing `EventEditorThenBatchSaveDuplicateTests`
  in its current form.
- `writeChain` ordering, against an in-memory `CalendarPersisting` fake: N rapid
  `setNumberOfColumns` produce N sequential writes whose final payload equals the
  final state. This is the test that the double-persist bug can never return.
- The store's only `import` list contains no `CorePersistence` — asserted by a
  grep-based test or a lint rule in CI.

### 12.4 View models

Each of the four view models gets a test that constructs it with a real assembler and
asserts that its projections reflect the store, and that its commands move the state.
They are plain structs, so no observation machinery is needed to test them.

- `AddEditEventListViewModel.events` is empty, then reports the assembly's events
  after `toggleDay`; `remove(_:)` dispatches `removeEvent`.
- `AddEditEventBatchViewModel.canSave` is false for an unnamed assembly and true once
  `setBatchName` lands; `nameBinding`'s setter dispatches rather than assigning.
- `AddEditEventBatchListViewModel.eventBatches` is **computed**: delete a batch via
  `assembler.send(.deleteBatches(...))` directly, bypassing the view model, and assert
  the projection drops it. This is the regression test for the stored-copy work-around
  the current code needs — §12.5.
- `AddEditEventViewModel` projections track `state.eventDraft`; `save()` dispatches
  `saveEventTapped`.
- No view model exposes a settable domain property. Asserted by keeping the four files
  free of `var` declarations other than the permitted view-scoped ones, checked in
  review and by a grep in CI.

### 12.5 The list-refresh regression

`AddEditEventBatchListViewModel.eventBatches` is currently a *stored* copy that must be
re-primed by hand in `onAppear` and `onChange(of: eventBatchesToDelete)`, because a
computed version was found not to re-render after a deletion. That work-around exists
only to compensate for holding a duplicate of state the reducer owns.

Two tests pin it so it cannot regress silently:

- unit: a batch deleted through the assembler — not through the view model — is absent
  from `AddEditEventBatchListViewModel.eventBatches` on the next read (§12.4);
- UI: `BatchEditCommitTests` already covers delete-to-empty navigation. The Stage 11
  addition covers delete-then-stay, where the day list must still show the remaining
  batches.

### 12.6 Integration and UI

- End-to-end on the store: `dayTappedInCalendar` → `toggleDay` → `setBatchName` →
  `saveTapped` yields one row in `batches` and one `writeCalendar` effect.
- Existing suites kept as-is: `SingleCalendarModelTests` (21),
  `EventBatchCreationTests` (37), `TwoSingleDayBatchesReproTests` (6),
  `SingleCalendarModelObjectBoxIntegrationTests` (19),
  `CalendarCacheIntegrationTests` (16), `AppNavigationTests` (21),
  `CoreDomainTests` (16), `DSKitTests` (17), `CalendarListFeatureTests` (18),
  `SettingsFeatureTests` (9).
- UI: `BatchEditCommitTests` (7) unchanged as the acceptance gate, plus the new
  multi-day scenario at Stage 11.

---

## 13. Decisions taken, and what was rejected

| Decision | Rejected alternative | Why |
|---|---|---|
| Manager *is* the store (`send`/`state`) | Manager exposing plain methods, plus a separate editor store | Two objects means two sources of truth and the reducer is unreachable from the views. Collapsing them is what makes requirements 2 and 3 the same change. |
| Generic `Store<State, Action>` as a reusable type | Non-generic specialised store | A generic store would need the year model, the persistence port and the write chain as generic parameters. The specialisation is the same code with real types. The article's shape is preserved: one state, one `reduce`, one `send`. |
| Separate pure `effects` derivation | Effects folded into the reducer | A reducer that writes cannot be unit-tested without a database. The derivation is a pure function returning `Equatable` values; only `perform` touches IO. |
| Navigation as state (`navigationRequest` + ack) | Effects that navigate | Navigation is a state transition a screen fulfils; keeping it in state means the reducer tests cover it. `AppRoute` stays payload-free because the payload is state. |
| Domain models in `CoreDomain`; DTOs internal to `CorePersistence`; `CalendarPersisting` port | Keep the models in the feature and map at the feature's persist edge | The feature cannot both keep the DTOs private and have the data layer produce the models without a shared module. `CoreDomain` already has zero dependencies, so adding it to `CorePersistence` cannot cycle. |
| Close the rule on all three DTOs: `CalendarListFeature` retargets from `CalendarDataSource` to `PinCalendar`, after which `CalendarDataSource` becomes internal too | Confine only `EventDataSource` / `EventBatchDataSource` | A half-enforced boundary is re-leaked within two commits. The cost is retyping `CalendarListFeature` and `CalendarCacheIntegrationTests` — mechanical and behaviour-free, since the list only ever read the five scalars `PinCalendar` carries. |
| `SingleCalendarModel` keeps its Combine subscription for calendar metadata | The manager subscribes to `CalendarCache.changes` and owns everything | Label, year, `isArchived` and column count are calendar metadata, not batch state. Putting them in the selection manager would widen its responsibility past its name. The manager remains the only *writer* of batches and the only owner of batch state. |
| `CalendarEvent` holds no calendar and no `dayKey` | Store a start-of-day `dayKey` and derive it via an injected provider | A `dayKey` is a second copy of a fact `date` already carries. It had to be recomputed by every setter of `date` and could drift when one did not, and the performance argument for it does not hold at a batch's size. Deriving it required coupling a value type to a service type, which then forced a non-defaulted initialiser parameter — a smell in itself. A calendar is needed to compare two events, not to hold one. |
| Mapping in the composition root, `PinCalApp/Root/` | Mapping inside `CorePersistence`; or in a separate bridging package | Putting it in `CorePersistence` means `CorePersistence` depends on `CoreDomain`, and the storage layer then knows the domain vocabulary exists — the storage layer should not. Putting the port in `CoreDomain` fails in reverse. A dedicated bridging package was built first and works, but it is a ninth package for ~150 lines when the app target is already the composition root and imports both. `PinCalAppTests` hosts the tests and, with two added package dependencies, can still reach `@testable CorePersistence` and `ObjectBox`. |
| Three types at the seam: `EntityMappable`, `RootMapper`, `CalendarStore` | One `CalendarPersistingAdapter` doing both; or a static mapper namespace | A transformer must not carry persistence — folding the cache in makes the mapping untestable without a store and hides which half does I/O. And a static namespace cannot be substituted: `CalendarStoreTests` proves the seam by injecting a mapper that uppercases names, which no amount of static-call refactoring would allow. Cost: a protocol over pure functions, which is normally avoided — worth it here because the translation is the only place two vocabularies meet, and that is exactly where a wrong mapping would be hardest to find. |
| The reducer carries `PCCalendarDataProvider`; it becomes `Equatable` | A separate `PCDayCalendar` value type for the reducer | The provider already held `startOfDay`, `isSameDay`, `month(of:)`, `year(of:)`, `currentYear` and `numberOfCurrentMonth`. A second wrapper around `Foundation.Calendar` would be a second source of truth, which is the duplication this refactor exists to remove. One `Calendar` in the domain layer, one way to compare days. |
| `pendingID: UUID` + `persistedID: Int64?` | `id: Int64` with a `0` sentinel | Removes the `ForEach` duplicate-identity failure, removes `hashValue` from identity, and makes "not saved yet" a value rather than a magic number. |
| `events: [CalendarEvent]`, sorted, day-unique in the assembly | `OrderedSet<CalendarEvent>` | `OrderedSet` dedupes by value, which is not the day rule, and would drop a legitimate event that happens to equal another. It would also add a package dependency to the feature layer for no benefit. |
| `onDayTapped` callback | `onChange(of: selectedDays)` | Removes the shared-mutable-bus failure mode and makes pre-seeding days safe by construction. |
| `writeChain` | Two concurrent `Task`s, or a debounce | Serialises writes so a later write cannot be lost behind an earlier one, and removes the only `Task.sleep` in the feature layer. |
| Keep all four view models, rebuilt as stateless projection facades | Delete them outright; or keep them as they are | Requirement 1 asks for the `AddEditListViewModel` rename and the companion decision is that views keep talking to a view model. Rebuilding them as projections is what removes the four copies of pending batch state; leaving them as they are is what causes it. §8.1 has the full shape and the view-scoped/domain-scoped rule. |
| View models as plain structs, not `@Observable` | Keep them `@Observable` | The assembler is the only `@Observable` object in the graph, so a computed projection read during body evaluation registers on `state` and refreshes correctly. Two observation registrations — one on the store, one on each view model — is a second thing to keep in sync for no benefit. `AddEditEventBatchListViewModel` stays `@Observable` because it has real view-scoped state. |
| Two year models, one builder, one projector | One shared year model | The main calendar and the editor navigate years independently and the UI tests target the editor's calendar. The duplication worth removing is the *logic*, and that is extracted. |
| No ObjectBox migration stage | Add one for safety | Not needed: `PPCalendar.eventBatches` is `ToMany<PPEventBatch>`, and the `*DataSource` structs are plain projections, not entities. The schema, the generated `EntityInfo` and every stored row are untouched (§3.3). |

---

## 14. Test execution

The suite is 258 tests. 229 unit tests take 90 s; the 29 UI tests take 847 s. **90% of
the wall clock is XCUITest**, and that is what makes the run hard to fit in a tool
call.

### 14.1 What went wrong, and the fix

`MobileBuildMCP_test_sim` has a client-side request timeout. With no `-only-testing`
filter it runs the whole `PinCalApp.xctestplan` — 229 unit plus 29 UI, ~15.6 min — and
the call fails with `MCP error -32001: Request timed out` before the suite finishes.
Nothing is wrong with the tests; the call outlasts the request.

The fix is `timeoutMs` on the tool, which is a real parameter and was verified up to
40 minutes:

```jsonc
{ "extraArgs": ["-only-testing:…"], "progress": false, "timeoutMs": 2400000 }
```

### 14.2 What was measured, including what did not work

| Change | Result |
|---|---|
| `timeoutMs: 600000` / `1800000` / `2400000` | **Works.** Batches complete reliably; the 40-minute ceiling was not reached by any batch. |
| Batching by target (`-only-testing` per group) | **Works.** Four calls, each well inside the limit, and each yields a per-target number for the baseline. This is what `TEST_BASELINE.md` records. |
| `-parallel-testing-enabled YES` + `-maximum-parallel-testing-workers 4`, 97 unit tests | **No gain: 55.7 s → 53.0 s.** The unit runs are dominated by build, install and launch, not by test execution, so there is nothing to parallelise. |
| `-parallel-testing-enabled YES` + 4 workers, 7 UI tests | **No gain: 268.3 s → 266.4 s.** Flags are accepted, but the UI tests do not actually run concurrently. Each XCUITest test relaunches the app and drives real taps, scrolls and waits, and the suite is already at its intrinsic cost. |
| `-default-test-execution-time-allowance 120` / `180` | **Accepted, no false positives.** Observed per-test cost is 26-38 s for UI, so a 180 s ceiling is ~5x headroom. Its value is not speed: a hung test now fails at the allowance instead of stalling the batch until the request times out. |

So: **there is no meaningful way to make the suite itself faster.** The cost is
intrinsic to XCUITest. What can be made constant is the *shape* of the run.

### 14.3 The constant-time routine

Use per-stage gates with a known duration rather than one open-ended suite
(§11.1). Three shapes, all bounded:

```jsonc
// A. Inner loop — ~35 s
{ "extraArgs": ["-only-testing:SingleCalendarFeatureTests"],
  "progress": false, "timeoutMs": 300000 }

// B. Batch-UI gate — ~267 s
{ "extraArgs": ["-only-testing:PinCalAppUITests/BatchEditCommitTests",
                "-parallel-testing-enabled", "YES",
                "-maximum-parallel-testing-workers", "4",
                "-default-test-execution-time-allowance", "180"],
  "progress": false, "timeoutMs": 600000 }

// C. Full gate — ~15.6 min
{ "extraArgs": [], "progress": false, "timeoutMs": 2400000 }
```

The parallel and allowance flags are kept in the routine even though they do not speed
anything up: they are free, and the allowance is what converts a hang from a
15-minute stall into a 3-minute failure.

### 14.4 Bypassing the timeout entirely

For a full-suite run, do not go through the tool. Two options, both already available:

- `xcodebuild test` against `PinCalApp.xcworkspace` with the same `-only-testing`
  batches, in a terminal. No request timeout at all, and the same `.xcresult` bundles
  are produced for baseline comparison.
- `Packages/AutoTestRunner`, an executable target that already exists in the repo for
  this purpose and is currently not referenced by the Xcode project. Wiring it as a
  scheme is a small task and is worth doing before Stage 0 if full-suite runs are
  expected to be frequent.

### 14.5 A caution on the baseline

The baseline was recorded as four separate batches, not one unfiltered run. A single
unfiltered `test_sim` with a raised `timeoutMs` is expected to work but has not been
verified end to end; batching is the verified path and it has the side benefit of
producing the per-target counts the baseline file needs. If a future stage does run it
unfiltered, record the split it into the baseline file anyway so the comparison stays
like-for-like.

---

## 15. Risks

| Risk | Mitigation |
|---|---|
| Stage 3 touches the data layer, where user data lives | No schema change (§3.3), so there is no migration and no write of a new format. `CalendarCacheIntegrationTests` (16) plus `SingleCalendarModelObjectBoxIntegrationTests` (19) must stay green unchanged. |
| Stage 4 is wide but shallow — four modules retyped at once | Split if needed into 4a (`CorePersistence` consumers) and 4b (app root). Neither needs new tests. |
| Stage 8 is large: five views rewritten, four models deleted | Split into 8a (event list + event editor) and 8b (batch editor + day list) if review warrants. Each half is independently reviewable; neither needs new tests. |
| Removing the `selectedDays` observation changes tap behaviour on the main calendar | Stage 7 lands the callback and the dispatch together, behind the existing manager and selection-mode tests, before any view is rewritten. |
| The duplicate-batch bug reappears through a path the tests miss | The adoption logic is one pure function in `syncCalendar` with one regression test, instead of a dictionary mutated from two call sites. |
| UI tests depend on accessibility identifiers | `TEST_BASELINE.md` records every one the suite asserts. Keeping them is a stated constraint on Stage 8. |
| `PCCalendarDataProvider.init` overwrites the time zone and locale of the calendar it is passed, so a test cannot pin either | Harmless today, because every caller passes `Calendar.autoupdatingCurrent` and its values are already the current ones. Date assertions are written to be zone-agnostic. Changing it is a behaviour change to shared code and is not in scope here; if it ever needs fixing it belongs in its own stage with the calendar-grid tests. |
| Requirement 4 is easy to re-leak | Invariant 3, plus the Stage 6 store test that asserts the manager's import list, plus a grep-based CI check on `SingleCalendarFeature`. |

---

## 16. Known bug — fix last

Recorded, not fixed. Do not start this until Stages 4b–11 are done and green: the
refactor replaces the machinery this bug lives in, so fixing it first risks fixing
behaviour that is about to be deleted.

### 16.1 Report

**STR**

1. Open a calendar, or create a new one.
2. Tap a day that has no events — say Oct 4 — which opens the batch editor for a new batch.
3. Change the batch name. Go into the event in the list, change its name, press Save.
4. Back in the batch editor, select Oct 5, Oct 6 and Oct 7. Press Save.
5. Back on the calendar, tap Oct 7.
6. In the batch editor, remove Oct 4, Oct 5 and Oct 6. Press Save.

**AB** — the batch list is empty.

**EB** — the batch list should contain a batch with one event, on Oct 7.

### 16.2 Status: pre-existing, not a refactor regression

Confirmed by inspection of the working tree: nothing modified so far touches this
path. `PCEventsSelectionManager`, all four `AddEdit*ViewModel`s, `AddEditEventListView`,
`AddEditEventBatchScreen` and `SingleCalendarView` are all untouched. The two files that
*are* modified — `CalendarCache` and its integration tests — changed additively
(`AsyncStream` feed, plus a new `loadedCalendars()`), and the calendar-list `fetch()` is
not on this path. Treat this as an existing defect that the refactor must not make
worse, not as damage already done.

### 16.3 Where to look — hypotheses, all UNVERIFIED

None of these has been confirmed by running the repro. They are the places a reader
should start, in the order given.

1. **The removal path empties the batch.** `PCEventsSelectionManager.removeEvents(at:)`
   removes by index; `AddEditEventListViewModel.remove(_:)` resolves that index through
   `firstIndex(of:)` on value equality. If the row the view hands back is a stale copy,
   the index can address the wrong event, and three removals could empty all four.
   Symptom to distinguish: does the *editor* still show the Oct 7 event when Save is
   pressed, or is it already gone?
2. **`canSave` / the `didSave` branch treats an emptied batch as a delete.**
   `AddEditEventBatchViewModel.canSave` only requires a name and a colour, never a
   non-empty event list, so an emptied batch is committable. And
   `AddEditEventBatchScreen` treats `viewModel.eventBatch?.events.isEmpty == true` as
   "the batch was deleted" and navigates to the calendar root — the exact shape of the
   reported AB, including a list that ends up empty.
3. **`commit` drops the row.** In `PCEventsSelectionManager.commit`, a batch with no
   events is removed from `batches` and not re-added. If hypothesis 1 or 2 empties the
   event list, the row is deleted rather than updated. This is the most direct route to
   "the batch list is empty".
4. **`eventBatchId` is still 0 at the third save.** `AddEditEventBatchViewModel.eventBatchId`
   is set once in `load()` and never refreshed after the store assigns a real id, so
   commits keep relying on `persistedIDsByPendingTimestamp` to resolve identity. If that
   adoption did not happen for this session, the final commit is keyed on a pending
   UUID that no longer matches any row and appends instead of replacing.
5. **The orphaned-event cleanup in the storage layer.**
   `ObjectBoxCalendarStorage.saveCalendar` removes events no longer referenced by a
   batch, and that file already carries a warning that getting the relation order wrong
   makes `applyToDb()` fail and *silently empty* a batch's events. This repro removes
   events, so it walks that path. Worth checking what is actually in the store after
   step 6, directly via `store.box(for: PPEventBatch.self).all()`.
6. **`date` drift, lower priority.** `AddEditEventBatchViewModel.date` is set only in
   `load()` and is not updated when days are added, so the persisted batch keeps
   `date == Oct 4` while holding an Oct 7 event. `PCEventsSelectionManager.batches(for:)`
   also matches on `batch.date`, so this can affect which day a batch is listed under.

Hypothesis 5 also has a cheap, decisive test: reproduce the six steps, then inspect the
store directly rather than the UI. That separates "the row was deleted" from "the row is
there but the list query misses it", which the UI alone cannot distinguish.

### 16.4 Acceptance for the fix

- A new UI test in `PinCalAppUITests/BatchEditor/`, encoding 16.1 step for step, asserting
  the Oct 7 batch list contains exactly one batch with exactly one event. It must fail on
  the current code first — verify by running it before the fix, as was done for
  `CalendarListRefreshTests` (§14.6). A test that passes against the broken build is worse
  than no test.
- The pull gesture is a **coordinate press-drag, not `swipeDown`** — see
  `CalendarListRefreshTests.pullToRefresh` for the measured reason.
- Cards are identified by name text, not `card-name-field-<id>`, which only exists while a
  card is being renamed.
- The full suite must hold at the Stage 0 baseline in `TEST_BASELINE.md`, plus the tests
  added since.
- If the fix removes the `isEmpty`-means-delete behaviour, that is the moment
  `BatchAssembly.resolved(against:)` (§5.4) takes over the decision, and hypothesis 2
  becomes structurally impossible rather than merely guarded.
