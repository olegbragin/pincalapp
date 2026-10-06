# AGENTS.md

Working notes for coding agents on this repository. Deliberately short: this file says **how
to work here**, not what the architecture is. The reasoning lives in doc comments next to the
code, where it can't go stale, and `TEST_BASELINE.md` holds the project's history.

## Layout

Paths below are relative to this file, which is the repository root.

- `PinCalApp.xcworkspace` — the iOS app. Everything builds through this workspace.
- `Packages/*` — feature and domain packages, one per bounded concern.
  `CoreDomain` holds types, `CorePersistence` holds storage, `DSKit` holds shared UI,
  `SingleCalendarFeature` holds the batch-assembly feature.
- `Packages/AutoTestRunner` — runs the whole suite on a simulator.
- `.swiftformat` / `.swiftlint.yml` / `scripts/sort_imports.py` — the formatting setup. See
  **Style → Formatting** before changing whitespace or import order by hand.
- `TEST_BASELINE.md` — the project's testing history and conventions.

## Building and testing

**Always verify through the iOS workspace.** This is the single most expensive mistake here.

### Use the MobileBuildMCP tools, not a hand-typed `xcodebuild`

The MCP server is the build and test interface here. Its session already has the workspace, the
scheme and a dedicated AutoTest simulator configured, so there is nothing to derive and no reason
to reach past it.

```
# Once per session, before the first build/run/test — not optional
MobileBuildMCP_session_show_defaults

MobileBuildMCP_build_run_sim                      # build, install, launch, capture logs
MobileBuildMCP_test_sim                           # run the tests
```

Both take empty arguments once the defaults are right. Pass `extraArgs` for `-only-testing:…`,
`-parallel-testing-enabled NO`, or anything else you would have put after `xcodebuild`.

This is not a style preference. A whole session was spent driving a *different* simulator than the
one the session had configured — typing `-destination "platform=iOS Simulator,id=B1542052-…"`
into dozens of commands while the defaults named `E368D458-…` — and hand-managing lifecycle that
the tools do for you. That is the cost of skipping this, and it is a real one.

The `installcoordinationd` / `IXSPlaceholder` failures below are **not** part of that bill: those
happen through `AutoTestRunner` too, which drives this same server. Two different causes, and only
one of them is avoidable.

**Two rules that follow:**

- **Never type a simulator UDID.** If the configured one is wrong, fix it with
  `MobileBuildMCP_session_set_defaults` (`simulatorId` / `simulatorName`), choosing from
  `MobileBuildMCP_list_sims`. A UDID you found with `xcrun simctl list` is a device nobody is
  tracking, and it will be half-erased from an unrelated run.
- **`session_show_defaults` first, every session.** It is cheap, and the alternative is
  discovering mid-run that the scheme or simulator was never what you assumed.
- **But "configured" is not "valid".** `show_defaults` happily reported a simulator
  (`E368D458-…`) that no longer exists on this machine; `test_sim` then failed with *"Unable to
  find a device matching the provided destination specifier"*. Check it against
  `MobileBuildMCP_list_sims` and correct it with `session_set_defaults` — a stale default fails
  late and looks like a tool problem rather than a config one.

### The whole suite: `AutoTestRunner`

```
cd Packages/AutoTestRunner && swift run AutoTestRunner --profile iphone   # or: ipad
```

One command: builds, installs, launches, runs every target, prints a pass count. It drives
mobilebuildmcp underneath — a failure surfaces as `error: mobilebuildmcp failed with exit code 1`,
with the result bundle path above it.

A green run on one target is not a green suite; the targets you did not name are the ones that
were not run.

### When `xcodebuild` is still the right call

Only to narrow to a single test while iterating — reproducing a failure, or re-running one suite
three times to tell a flake from a real bug:

```
# A Swift Testing suite: the class is enough
xcodebuild test -workspace PinCalApp.xcworkspace -scheme PinCalApp \
  -destination "platform=iOS Simulator,id=<UDID>" \
  -parallel-testing-enabled NO \
  -only-testing:SingleCalendarFeatureTests

# An XCTest UI test: the METHOD name, not just the class, or it silently runs nothing
xcodebuild test -workspace PinCalApp.xcworkspace -scheme PinCalApp \
  -destination "platform=iOS Simulator,id=<UDID>" \
  -parallel-testing-enabled NO \
  -only-testing:PinCalAppUITests/EditorBackNavigationTests/testBackOutOfEventEditorLeavesTheBatchEditorUsable
```

Prefer `MobileBuildMCP_test_sim` with the same filter in `extraArgs` first; reach for the shell
only when the MCP filter cannot express what you need.

`-parallel-testing-enabled NO` is deliberate in both of those, not a leftover from when serial was
mandatory: one target has nothing to distribute, so four clones would only add boot and install
time. Drop it once you are running more than one target.

### Gotchas that have each cost a run

- **`Executed 0 tests` does not mean nothing ran.** That line counts *XCTest* only. Swift
  Testing suites report separately as `Test run with N tests in M suites`. `test_sim` prints
  `Discovered N test(s)` before running, which is the number to check when a filter is suspect.
- **A failed install is the simulator, not the code.** `installcoordinationd` or
  `IXSPlaceholder`, with every unit test already green, means the test *runner* was never
  installed. It happens through `AutoTestRunner` too, so it is not an artefact of the tool you
  chose. Remedy: `MobileBuildMCP_boot_sim`, or `MobileBuildMCP_erase_sims` when a re-boot is not
  enough — the iPad AutoTest device needed an erase before it would install anything at all.
  Never read it as a regression.
- **A stale `.xctest` bundle in DerivedData fails as *"Trying to load an unsigned library"*,**
  reported as `xctest (…) encountered an error` under a `System Failures` heading rather than as
  a test failure. No test in that bundle ran. Delete the product bundle
  (`rm -rf <DerivedData>/Build/Products/Debug-iphonesimulator/<Target>.xctest`) and re-run.
- **`swift build --package-path Packages/SingleCalendarFeature` cannot work.** That package
  uses iOS-only UIKit APIs, so it does not compile for macOS. It also means its tests cannot be
  run with `swift test` — use the workspace. The other packages do build for macOS.
- **Parallel testing is available; the default is serial.** Every unit target is marked
  `parallelizable` in `PinCalApp.xctestplan`, so parallel execution is a worker count away:
  `AutoTestRunner --parallel-workers 4`, or `-parallel-testing-enabled YES
  -maximum-parallel-testing-workers 4` in `extraArgs`. It defaults to **1**, which is one
  destination and no clones. This reverses an earlier decision that serial was mandatory — see
  "Parallel testing was never a coupling problem" below for what was actually wrong.
- **Do not trust a wall-clock number measured on this machine without checking the load first.**
  `uptime` on this host has read anywhere from 5 to 113 during a single session, with no
  simulators booted and no compiler running, and the same configuration has measured 27s and
  106s on different hours. Parallel-vs-serial has **not** been reliably measured: an early sample
  suggested four workers was ~2.5x slower than one (27s vs 59-77s), but a later one-worker run
  came in at 106s — slower still — so that comparison was measuring the host, not the tests.
  The default of 1 is conservatism, not a measured optimum. Interleave the configurations and
  watch `uptime` before concluding anything about which is faster.
- **`PinCalAppUITests` is deliberately *not* `parallelizable`.** Xcode will not distribute UI
  tests; they drive one app against one device. They run serially alongside the unit targets
  rather than being excluded.
- **Test targets** are `SingleCalendarFeatureTests`, `AppNavigationTests`,
  `CorePersistenceTests`, `DSKitTests`, `PinCalAppTests`, `PinCalAppUITests`,
  `CalendarListFeatureTests`. Roughly 420 tests total on iPhone, of which 49 are UI tests and
  take about 20 minutes; everything else is seconds.
- **Run both profiles.** The iPad profile is the only run that checks the calendar-switch
  guarantees — see "A multi-select session is per calendar" below for the measured reason.
- **When using ripgrep, type flags deliberately.** `-r` is `--replace` (it takes an argument),
  not "recursive". `rg -rln "x"` silently eats `ln` as the replacement and matches nothing.
  Prefer the `grep`/`glob` tools over hand-built `rg` invocations.
- **Generated files churn.** `LocalizedStringKeyExtension.swift` is regenerated by any build
  that touches the string catalog and its only diff is a timestamp. Do not commit that.

### Parallel testing was never a coupling problem

Worth recording, because the reason this suite can now run in parallel is not the one the original
`-parallel-testing-enabled NO` implied.

Serial was justified as "the simulator cannot run the suite in parallel, and parallel runs produce
order-dependent failures". There was never any test coupling to fix. **`.serialized` appears zero
times in the repository**, so Swift Testing was already running every suite concurrently inside the
process — with the flag *off*. `-parallel-testing-enabled` is orthogonal to that: it adds
concurrency *between destinations*. So the flag was never protecting against tests interfering with
each other, and no amount of decoupling work was going to make it safe.

What parallel actually introduced was **load**. Four clones on one Mac oversubscribe the CPU, and
the casualties were the tests whose assertions are wall-clock budgets rather than conditions —
`waitForWrites(1, timeout: .milliseconds(300))`, a 400 ms autosave ceiling, a 50 ms progress timer.
The recorded "hard main-actor contention crash that poisoned 136 tests" reproduced as **one**
failure: `PCNameAutosave/Continuous typing still writes`, which asserted `fired >= 1` inside a fixed
400 ms window while the ceiling it was testing was 200 ms of main-actor timer. Under load the loop's
wall clock ran out before the starved main actor ran the timer.

That test now keeps typing *until* the write lands, so the trailing debounce cannot satisfy the
assertion after typing stops — otherwise deleting the ceiling entirely would still have passed it.

**The lesson for the next wall-clock assertion:** assert the condition, and if the thing under test
is a *bound* rather than an event, keep the triggering activity running until the bound is hit.
`waitFor`-style helpers are the model. A fixed window around a real timer measures the machine.

**Parallel is not established as a speedup, in either direction.** Early samples said four
workers was ~2.5x slower than one (394 unit tests: 27s against 59-77s), on the reasoning that
clone boot and install cost more than the tests do. A later one-worker run measured **106s** —
slower than any four-worker run — while `uptime` read anywhere from 5 to 113 with no simulators
booted and no compiler running. So those numbers were measuring a degrading host rather than the
tests, and the comparison is void. What *is* solid is the failure mode: at four workers exactly
one test broke, and it was a wall-clock budget (above). What is **not** solid is any claim about
which worker count is faster. Settle it by interleaving configurations on an idle machine, not by
trusting a number already in this file.

### UI-test launch arguments

Pass these so runs are deterministic; all seeded launches should set the first one.

- `-UITestSeedData` — load the seeded calendars
- `-UITestColumns <n>` — force the year grid's column count (1 gives large tappable cells)
- `-UITestUndoWindowSeconds <n>` — lengthen the archive-Undo toast's window
- `-UITestNameAutosaveSeconds <n>` — set the typed-name debounce; `0` makes it write on the
  next scheduler pass instead of 250 ms later

## Style

### Formatting is a tool, not a habit

`SwiftFormat` owns formatting; `SwiftLint` reports everything else. Both are **global
Homebrew installs** (`brew install swiftformat swiftlint`), deliberately not vendored, so
nothing pins the version. Verify with `swiftformat --version` / `swiftlint version` before
trusting a diff — a `brew upgrade` can change output and produce churn that is not yours.

Config is committed, so read these two before hand-formatting anything:

- `.swiftformat` — formatting. Every value was measured against this codebase.
- `.swiftlint.yml` — 50 rules disabled, all of them rules that autocorrect whitespace or
  tokens SwiftFormat also moves.

```
swiftformat .                          # apply formatting
swiftformat --lint .                   # check only: prints "N/182 files require formatting"
python3 scripts/sort_imports.py .      # apply import order
python3 scripts/sort_imports.py --check .
swiftlint lint --quiet                 # report; 47 pre-existing violations, not a gate yet
```

The two writers (`swiftformat`, `sort_imports.py`) are idempotent and do not step on each
other. **Run both** — running only one is how you get a half-formatted tree. `swiftlint` only
reports, so it never conflicts with anything.

#### The two tools fight unless the config stops them

This is the thing to know before changing either config. Where both believe they own a line,
they rewrite it into two different forms, permanently, and the symptom is a formatting commit
that keeps reappearing in review. Three SwiftFormat rules are disabled for exactly this:

| disabled | what it would do |
| --- | --- |
| `sortImports` | re-sorts the block and loses the system/app grouping |
| `blankLinesBetweenImports` | deletes the separator between the groups |
| `blankLineAfterImports` | reads a comment *inside* the block as the block's end |

The 50 disabled SwiftLint rules are the same idea from the other side. Note the selection
criterion is **not** SwiftLint's `kind` column: `comment_spacing` and `mark` are labelled
`kind: lint` and still reported 4377 violations against SwiftFormat's own normalisation.
Filter on "does autocorrect move whitespace", not on `kind == style`.

#### What the formatter is not allowed to do

Both of these **broke the build** when enabled. They are off deliberately; do not re-enable
them without running the tests.

- `redundantSelf` (`--self remove`). Stripped `self.` from 61 sites, every one inside an
  OSLog string interpolation — an autoclosure context where the compiler *requires* explicit
  `self.`. `--self init-only` is not safe either; it still hit 17, because `didSet` counts as
  initialisation. Explicit `self.` is the prevailing style here, so there is nothing to gain.
- `preferKeyPath`. Rewrote `allSatisfy { $0.colorName.isEmpty }` as `allSatisfy(\.colorName.isEmpty)`.
  `allSatisfy` takes a *throwing* closure and a key-path-as-function cannot carry `throws`, so
  the compiler picks the throwing overload and reports the call unhandled. The rule is
  `preferKeyPath`, **not** `redundantClosure` — disabling the latter changes nothing.

#### Imports

`--import-grouping` cannot express "system first, then application". It only accepts `alpha`,
`access-control`, `length`, `testable-first`, `testable-last`, and all of them collapse the
block into one alphabetical run. Apple's `swift-format` does not reorder imports at all. So
`scripts/sort_imports.py` owns it, and SwiftFormat stays out of the block. The order carries
the grouping — there is no blank line between the groups, so nothing marks the boundary to a
reader:

```swift
import Foundation      // system
import SwiftUI
import CoreDomain      // application
import DSKit
@testable import SingleCalendarFeatureTests
```

First-party modules are discovered from `Packages/*/Package.swift`, so a new package needs no
script change. It bails out on `#if`-wrapped imports, and on any manifest whose
`// swift-tools-version:` it would displace — that comment is only valid on line 1.

#### Never format generated or vendored code

Roughly 2100 files under `Packages/*/.build` are third-party SPM checkouts, and two source
files are generated. `--exclude` and `excluded:` match path **prefixes**, so a bare `.build`
does not reach `Packages/DSKit/.build` — the glob `**/.build/**` is required. That one detail
was worth 6202 phantom violations before it was fixed.

- `**/generated/**` — ObjectBox entity code. Already carries `// swiftlint:disable all`.
- `**/LocalizedStringKeyExtension.swift` — regenerated by `GenerateLocalization` on any build
  that touches the string catalog, so it never converges. Its only diff is a timestamp.

### Declaration order inside a type

Both properties and methods are grouped, and within each group ordered by
**static → instance**, then by **visibility: public → internal → private**.

- **Properties** come first, then `init`, then **methods**.
- **Methods**: `static` before instance; within each, public before internal before private.

Most of the codebase already follows this. Two things to watch:

- Computed properties (`var x: Bool { ... }`) are properties, so they belong in the property
  block with the stored ones.
- A `private` init still separates the two blocks. `PCEventBatchAssembleUnitOfWork` is the
  reference example.

### Comments

Document **why**, especially why something is the way it is rather than the obvious
alternative. The house style is to record what was tried and why it was wrong:

```swift
/// Whether the calendar may be switched away right now.
///
/// False only while a save has failed. In-flight writes are *not* a reason to block — the
/// switch flushes them, and blocking on every keystroke-save would make the calendar feel
/// sticky for no benefit.
```

When replacing a rule, keep the old reasoning. Half of `PCEventSelectionReducer` reads as a
record of decisions that were made and why — that is deliberate, and deleting the history
loses the reason the current shape exists.

Prefer a comment explaining a *decision* over one restating the code. Never add a comment that
only narrates what the next line does.

## Architecture you should not undo

These are load-bearing. Each was arrived at by fixing a bug, and the reasoning is in the code.

- **The store is the only writer.** `PCEventSelectionManager.send` is the single mutation
  point; `pcEventSelectionReducer` is pure. Do not add `didSet` observers or a second path
  into state.
- **There is one store per calendar, and `PCAppSession` owns them.** Not one for the
  process — that was the rule until it cost data. `state.calendarID` is written in exactly one
  place (`syncCalendar`), behind a guard that accepts only the calendar it already holds, so a
  single app-wide store meant the **first calendar ever opened pinned it for good**: a second
  calendar's sync was rejected, it rendered the first calendar's markers, and every write still
  targeted the pinned id — with a destructive `saveCalendar`, a tap in the second calendar wrote
  into the first calendar's row. Get a store from `session.eventSelection(for: calendarID)`; never
  hold one app-wide, and never inject one above `CalendarDetailView`.
- **A multi-select session is per calendar too, so leaving a calendar has to end it.** The stores
  are *cached*, so a session would otherwise come back painted and unendable. Three places end it,
  deliberately overlapping: `SingleCalendarView.onDisappear`, `CalendarDetailView.onDisappear`,
  and `RootNavigation.switchCalendar` via the `willLeaveCurrentCalendar` hook. Only the last one
  survives on iPad — measured, with all three disabled, `testSwitchingCalendarEndsAMultiselectSession`
  is green on iPhone and red on iPad, because a phone pops the calendar view away while an iPad
  replaces the detail column in place. **So run the suite on both profiles**; the iPad profile is
  where the calendar-switch guarantees are actually checked, and an iPhone-only green run has
  never exercised them.
- **Inject the store at the app root, per calendar.** `PinCalAppApp` injects
  `session.currentEventSelection`. Two traps, both of which cost a day:
  - **Not below the `NavigationStack`.** A `navigationDestination`'s content is rendered in the
    stack's context and does not reliably inherit an environment applied under it. Injecting on
    `CalendarDetailView` trapped every pushed editor with `_assertionFailure` inside
    `EnvironmentValues.subscript.getter` — a crash report with no app frame in it at all.
  - **Not from an `onChange`.** The id has to be set from inside the navigation mutation
    (`RootNavigation.onCalendarChanged`), because an observer runs a frame *after* the render that
    acted on the new value. A frame of staleness means the detail is built against one store
    while every view reads another, and the symptom is a day list that opens empty.
- **A calendar that stops existing stops being selected.** `RootNavigation.detailCalendarID` used
  to be written in exactly one place and never cleared, so archiving or permanently deleting the
  calendar on screen left the detail column rendering a calendar that was gone — blank for a
  deleted one, since `.empty` draws an `EmptyView` — with the app root still injecting its store.
  `RootNavigation.closeCalendarIfSelected(_:)` is now the only thing that can clear it.
  - **The list reports it, from its existing change feed.** `CalendarListViewModel.onCalendarRemoved`
    fires off `applyChange`'s `.removed` case — the subscription was already there and already
    folded removals. Do **not** add a second `for await` over `managing.changes()` in a view body
    to catch this; the list is the screen that watches calendars, and one owner of a subscription
    is worth more than a second one placed closer to whoever needs the news. `.removed` is exactly
    "archived or deleted": those are the only operations that publish a removal, and a restore
    publishes a *change*, which is why Undo does not close anything.
  - **Three things about the close are load-bearing.** It runs `willLeaveCurrentCalendar` **while
    the id is still set** (the hook reads it to find the store whose session must not outlive its
    calendar); it clears `path` (a pushed `.batchEditor` over a deleted calendar is built against a
    store that can no longer write); and it notifies `onCalendarChanged(nil)` **before** clearing
    the id, like an opening does. It deliberately does *not* consult `canLeaveCurrentCalendar`:
    settling a write chain for a calendar on its way out means writing to a row that is leaving.
- **Ending a session deletes a batch that has no days.** `endingMultiSelectSession` is the single
  place that decides, shared by Confirm and Cancel — two copies of it is how Confirm came to stage
  an event-less batch while Cancel left the row behind. Normally the tap that takes the last day
  has already deleted the row, so this is the guarantee rather than the mechanism.
- **Edits persist as they are made.** A mutation merges into `state.batches` immediately; only
  the *database write* is deferred. This is why there is no save-or-discard question, and it is
  why cancelling a pending debounced write is safe — the value is already in the state. If you
  change the merge, re-check that invariant.
- **There is no Save.** Neither editor has one; `AddEditEventBatchScreen` and `AddEditEventView`
  each have a single store-routed Back that is also their one addressable element. Every field
  writes through as it is edited, so Back has nothing to commit — with one exception: leaving
  an *emptied* batch deletes its row, which is the only way to delete a batch from the editor.
  Nothing gates on a batch having a colour any more, so there is no path where the user is stuck
  on an unsaveable edit.
- **An event's `date` carries a time of day.** It is deliberately not normalised to start-of-day;
  truncating it is what silently discarded the time picked in the event editor. Day *identity* is
  day-granular (`occurs(on:using:)`, `hasSameContent(as:using:)`, `isSnapshot(of:using:)`,
  `PCEventSelectionReducer.dayTappedInCalendar`) — keep those comparisons on days and leave the
  stored value alone. A freshly added day is midnight, which is the honest "unset".
- **`syncCalendar` must adopt every live assembly, not just the editor's.** A reload replaces
  `state.batches` wholesale with rows the database has given real ids, which strands any staged
  assembly still holding a `.pending(…)` key — and the next merge then *appends* instead of
  replacing. A multi-select session writes on every tap, so it reloads between every tap: four
  days tapped produced four batches holding one, two, three and four events. Adoption is one
  helper applied to both, and it matches on `isSnapshot(of:using:)` rather than equality, because
  the row in the database is the assembly as of the write and the assembly has usually moved on
  by the time the reload lands.
- **There are two day-marker payloads, and merging them reintroduces a reported bug.** The main
  calendar reads `state.dayEventColors` — every batch in the registry, which is what that panel is
  for. The batch editor reads `state.editorDayEventColors` — the staged assembly and nothing else.
  They were one payload, and the editor came up showing every batch's days: a batch created for an
  empty day appeared to already hold the days of the batch made before it. Worse than the clutter,
  because a marked day belonging to another batch is *added* to this one when tapped, not removed
  from that one — `toggling` only knows about the assembly — so the foreign days read as this
  batch's own and could not be acted on. Do not "simplify" the editor back onto
  `dayEventColors`.
- **Writes are chained.** `writeChain` makes two concurrent writers unrepresentable by having
  each write await its predecessor. Do not replace it with a bare `Task { }` — actor
  reentrancy means that is not ordered.
- **`saveCalendar` is transactional and read-modify-write.** It deletes every batch absent from
  the incoming set, then re-inserts. A dropped write is data loss, not a stale row.
- **Failures are surfaced, not swallowed.** `failedSave` blocks the calendar switch and raises
  a toast with Retry. A `try?` over a persistence call is a bug.
- **Accessibility identifiers go on leaf views only.** An identifier on a container shadows its
  descendants' identifiers and breaks queries for everything inside it. This cost 30 tests once.

### UI tests

- **Match on accessibility identifier, never on label.** A label is neither unique nor stable.
  Both editors used to have a checkmark labelled "Save", and so does the multi-select confirm on
  the main calendar, so `toolbarAction("Save", in: app)` could resolve to any of the three
  depending on what was on screen. Give the thing under test an identifier and query that.
- **Every screen a test waits on needs at least one addressable element.** Until the checkmarks
  went, `batch-save-button` was doing two unrelated jobs in ~28 places: the way *out* of the
  editor, *and* — because nothing else on that screen was addressable — the way to tell the
  editor was open. When an affordance is removed, check whether it was load-bearing for a test
  in a way nothing obvious suggests.
- **`typeText` returns when the keys are sent, not when the app has acted on them.** A test can
  navigate away with the last keystroke in flight, and in the batch editor that loses the edit
  outright: leaving clears `state.assembly` and `editing` declines a name change when there is no
  assembly, so the trailing characters are dropped. It surfaces as a flake in whichever test lost
  the race, with the failure naming the batch rather than the typing. `replaceText` waits for the
  typed text to land in the field — keep that wait.
- **`replaceText`'s triple-tap selection is itself flaky, and a suffix wait hid it.** When the
  tap misses, the text is *appended* ("New eventCycle"). The original rule was to wait for a
  **suffix** and leave the value to the caller, on the reasoning that a caller's own name
  assertion was the right place to hear about the append — but it never was: the append sailed
  through the suffix wait, and the test failed minutes later on a row label that never matched,
  naming the list rather than the typing (measured in both runs of that flake). Every caller
  passes a full replacement, so `replaceText` now waits for **equality** and *repairs* the miss
  by re-selecting and retyping — up to three attempts — before failing as a typing failure.
  Assert what the caller asked for, and fix the flake where it happens instead of reporting it
  downstream.
- A UI test that takes a screenshot or dumps the hierarchy is worth the seconds when a UI change
  has to be verified by hand — but say so in the report, separately from the suite result.

## Testing conventions

- Unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). New unit tests should
  too.
- UI tests must be **XCTest** — `XCUIApplication` has no Swift Testing bridge.
- Prefer polling for a condition over sleeping a fixed duration. The write chain is
  scheduler-driven, so a fixed wait is a flake that reads as "work was lost".
- **Wait on the content of the last write, not on a count.** Edits persist as they are made, so a
  three-edit sequence enqueues three writes down one chain; `waitForWrites(1)` returns after the
  first and `writes.last` is then the *wrong* write. Use `waitForLastWrite(where:)`. Asserting a
  count is only right when the count is the thing under test.
- **When a test drives an affordance, ask what the affordance was actually doing.** Half the
  `saveTapped` tests were asserting that a row which had already been written got written again —
  which passed while the feature had no real save step, because the button was what made it look
  like one. "I removed a button" is a prompt to re-derive every test that touched it.
- **Removing a UI affordance means removing what fed it, too.** An action no screen can send is a
  case nothing can exercise (`everyActionIsCovered` counts them), and a ViewModel projection no
  view reads is dead code kept alive only by its own tests — the `isDirty` and `canSave` pattern.
  Re-point those tests at the domain property instead of keeping the projection alive for them.
- When a test's *premise* changes (not just its expectation), say so in the comment and often
  rename the test. A test name that describes behaviour that no longer exists is worse than no
  test.
- **Check that a test can fail.** `flushOnNothingIsHarmless` declared a counter, never wired it,
  and asserted the counter was zero — it could not fail. A counter that is never mutated, or a
  fixture that builds a state the reducer cannot emit, is the same failure wearing a passing
  test's clothes. The compiler flags the first (`variable was never mutated`); the second needs
  reading for.
- If a test fails, establish whether the code is wrong or the test is wrong *before* changing
  either. Many failures in this repo have been harness problems.

## Things that are true and not obvious

- The XCUITest **runner reports `.phone`** even when driving an iPad
  (`UIDevice.current.userInterfaceIdiom` inside the runner is wrong). Detect a pad from the app's
  UI — the split view's sidebar toggle — not from the idiom.
- Seeding and tests use **days 1 and 2 of `Calendar.current`'s month**, so a run that crosses a
  month boundary does not fail on the fixture.
- `isDirty` was removed. "Has this been saved" is answered by `failedSave`, which records the
  outcome rather than the intent.
- Batch names default to `"New event"`, events to `"New event day"`. A batch name is optional —
  only colour is required to write one.

## Before you claim something works

- Re-read the diff. Generated-file churn and stray indentation accumulate silently.
- Run `swiftformat --lint .` and `scripts/sort_imports.py --check .` before reporting done.
  Both should print zero. If either wants to change something, the tree is not formatted, and
  a half-applied run is worse than either extreme.
- If you touched both tools at once, confirm they still agree: run
  `swiftformat . && scripts/sort_imports.py .` twice and check the second run is a no-op.
  Identical hashes across the two runs is the only proof they are not fighting.
- Report the number you actually measured, and say when it is stale. A green run before three
  phases of changes is not a green run.
- Distinguish "builds" from "verified". A toast with no test exercising it builds; it is not
  verified.