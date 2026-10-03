//
//  PCEventBatchAssembleUnitOfWorkTests.swift
//  SingleCalendarFeatureTests
//
//  Stage 5a's gate. The plan's §12.2, plus the two §12.1 invariants that belong to this
//  type rather than to the reducer that will call it: that two toggles on one day restore
//  the original count, and that applying an event onto an occupied day moves it.
//

import Testing
import Foundation
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

@Suite("PCEventBatchAssembleUnitOfWork Tests")
struct PCEventBatchAssembleUnitOfWorkTests {

    /// The domain layer's only `Foundation.Calendar` owner, used for every day
    /// comparison here.
    ///
    /// `PCCalendarDataProvider.init` forces the current time zone and locale, so a
    /// fixture calendar cannot pin them. Fixture dates are therefore built at midday UTC
    /// and the assertions are written to hold in whatever zone the tests run in.
    private let provider = PCCalendarDataProvider()
    private let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ month: Int, _ dayOfMonth: Int, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        return gregorian.date(from: components)!
    }

    /// A batch with explicit name and colour.
    ///
    /// Both are passed to the factory rather than applied afterwards, so an explicit `""`
    /// really does produce an unnamed batch. It used to be `if !name.isEmpty { renaming }`,
    /// which silently depended on `new` producing an empty name — and the moment `new`
    /// started defaulting one, `namedAssembler(name: "")` returned a *named* batch and the
    /// "no name" case stopped being tested without anything looking broken.
    private func namedAssembler(
        name: String = "morning",
        color: PCColorOption? = .option1,
        on anchor: Date? = nil
    ) -> PCEventBatchAssembleUnitOfWork {
        PCEventBatchAssembleUnitOfWork.new(
            anchor: anchor ?? day(6, 1),
            name: name,
            colorName: color?.colorName ?? "",
            using: provider
        )
    }

    // MARK: - Identity

    /// The default a new batch arrives with, pinned because a great deal rides on it: it
    /// is what makes a merely-tapped day savable, and it is what a user sees before they
    /// type anything.
    @Test("new(anchor:) arrives named and coloured, so a tapped day is savable immediately")
    func newSeedsOneEvent() {
        let assembler = PCEventBatchAssembleUnitOfWork.new(anchor: day(6, 1), using: provider)

        #expect(assembler.origin == .new)
        #expect(assembler.isNew)
        #expect(assembler.batch.events.count == 1)
        #expect(assembler.batch.name == PCEventBatchAssembleUnitOfWork.defaultBatchName)
        #expect(assembler.batch.colorName == PCColorOption.firstAvailable.colorName)
        #expect(assembler.batch.events[0].name == PCEventBatchAssembleUnitOfWork.defaultEventName)
        #expect(
            assembler.batch.events[0].colorName == assembler.batch.colorName,
            "the event inherits the batch's colour, so the event editor's own Save is enabled too"
        )
        #expect(assembler.canSave, "a merely-tapped day must be committable without any editing")
        #expect(assembler.adoptedPersistedID == nil)
    }

    /// The undefaulted shapes still have to be constructible — the reducer tests use them to
    /// reach a state `canSave` refuses, which is a real state and worth being able to build.
    @Test("new(anchor:) takes an explicit name and colour, including empty ones")
    func newTakesExplicitNameAndColour() {
        let assembler = PCEventBatchAssembleUnitOfWork.new(anchor: day(6, 1), name: "", colorName: "", using: provider)

        #expect(assembler.batch.name.isEmpty)
        #expect(assembler.batch.events[0].name == PCEventBatchAssembleUnitOfWork.defaultEventName)
        #expect(assembler.batch.colorName.isEmpty)
        #expect(assembler.canSave == false, "and canSave still reports why")
    }

    @Test("new(anchor:) normalises the anchor to the start of its day")
    func newNormalisesAnchor() {
        let anchor = day(6, 1)
        let assembler = PCEventBatchAssembleUnitOfWork.new(anchor: anchor, colorName: "", using: provider)

        #expect(assembler.batch.events[0].date == provider.startOfDay(for: anchor))
    }

    @Test("new(all:color:) holds one placeholder per selected day, sorted")
    func newAllSeedsOnePerDay() {
        let assembler = PCEventBatchAssembleUnitOfWork.new(
            all: [day(6, 3), day(6, 1), day(6, 2)],
            color: .option2,
            using: provider
        )

        #expect(assembler.batch.events.count == 3)
        #expect(assembler.batch.colorName == PCColorOption.option2.colorName)
        #expect(assembler.batch.events.allSatisfy { $0.colorName == PCColorOption.option2.colorName })
        #expect(assembler.batch.events.allSatisfy { $0.name == PCEventBatchAssembleUnitOfWork.defaultEventName })
        #expect(assembler.batch.name == PCEventBatchAssembleUnitOfWork.defaultBatchName)
        #expect(assembler.canSave)
        let dates = assembler.batch.events.map(\.date)
        #expect(dates == dates.sorted(), "order must not depend on tap order")
        #expect(provider.isSameDay(dates[0], day(6, 1)))
        #expect(provider.isSameDay(dates[2], day(6, 3)))
    }

    /// A nil colour is defaulted rather than honoured.
    ///
    /// The reducer refuses to confirm a session without a colour, so this is a defensive
    /// branch — and the two "a new batch" entry points should not disagree about what one
    /// looks like just because one of them was handed nil.
    @Test("new(all:color:) with a nil colour falls back to the first available colour")
    func newAllNilColor() {
        let assembler = PCEventBatchAssembleUnitOfWork.new(all: [day(6, 1)], color: nil, using: provider)

        #expect(assembler.batch.colorName == PCColorOption.firstAvailable.colorName)
        #expect(assembler.batch.events.allSatisfy { $0.colorName == PCColorOption.firstAvailable.colorName })
        #expect(assembler.canSave)
    }

    @Test("existing(_:) records the row it was opened from")
    func existingRecordsOrigin() {
        let batch = CalendarEventBatch(
            pendingID: UUID(),
            persistedID: 7,
            name: "morning",
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: day(6, 1), colorName: "eventColorOption1")]
        )

        let assembler = PCEventBatchAssembleUnitOfWork.existing(batch)

        #expect(assembler.isNew == false)
        #expect(assembler.origin == .existing(pendingID: batch.pendingID))
        #expect(assembler.canSave)
    }

    // MARK: - canSave

    @Test("canSave requires a colour, and does not care about the name")
    func canSaveRequirements() {
        #expect(namedAssembler().canSave)

        #expect(namedAssembler(name: "").canSave, "a nameless batch is still a batch")
        #expect(namedAssembler(color: nil).canSave == false, "no colour is the only refusal")
    }

    /// An emptied batch stays writable, because that is how it gets deleted.
    ///
    /// The reducer's `backTapped` treats "leaves with nothing to resolve" as *delete the row
    /// and return to the calendar*. Folding `!events.isEmpty` into `canSave` made that branch
    /// unreachable — and once there was a checkmark it was worse than unreachable, because the
    /// button's `isEnabled` read this flag, so it was *disabled* in exactly the state that
    /// would have triggered the delete. A user who removed every event had no way to commit
    /// the removal, and the only exit left was Back, which discards it.
    ///
    /// **Premise changed.** The name says "savable" because the flag used to gate a Save. It
    /// now gates only whether `editing` merges a row, and the delete hangs off leaving rather
    /// than off a flag. Both halves still have to hold, so both are still asserted.
    @Test("A batch with no events is still writable, which is what lets leaving delete it")
    func emptyBatchIsStillWritable() {
        let assembler = namedAssembler()
        let emptied = assembler.removingEvent(pendingID: assembler.batch.events[0].pendingID)

        #expect(emptied.batch.events.isEmpty)
        #expect(emptied.canSave, "the delete branches on emptiness, so this must not refuse it")
        #expect(
            emptied.resolved() == nil,
            "but there is still nothing to write, which is what keeps `editing` from persisting it"
        )
    }

    // MARK: - toggling

    @Test("toggling a day on then off restores the original event count")
    func toggleRoundTrips() {
        let assembler = namedAssembler()
        let original = assembler.batch.events.count

        let on = assembler.toggling(day: day(6, 2), using: provider)
        #expect(on.batch.events.count == original + 1)

        let off = on.toggling(day: day(6, 2), using: provider)
        #expect(off.batch.events.count == original)
    }

    @Test("toggling never leaves two events on one day, in either direction")
    func toggleKeepsOneEventPerDay() {
        var assembler = namedAssembler()
        // A day already holding an event, then a second toggle on that same day.
        let target = day(6, 2)
        assembler = assembler.toggling(day: target, using: provider)
        #expect(assembler.batch.events.filter { provider.isSameDay($0.date, target) }.count == 1)

        // Toggling the day that already holds the seeded event removes it rather than
        // adding a second.
        let seededDay = day(6, 1)
        let afterSecond = assembler.toggling(day: seededDay, using: provider)
        #expect(afterSecond.batch.events.filter { provider.isSameDay($0.date, seededDay) }.count == 0)

        // And no day anywhere holds more than one.
        for event in afterSecond.batch.events {
            let sameDay = afterSecond.batch.events.filter { provider.isSameDay($0.date, event.date) }
            #expect(sameDay.count == 1)
        }
    }

    @Test("toggling treats times on the same day as the same day")
    func toggleIsDayGranular() {
        let assembler = namedAssembler()
        // 6pm is a different instant from the seeded midday, but the same day, so this
        // is a toggle *off* of the existing event rather than a second event beside it.
        let lateEvening = gregorian.date(
            bySettingHour: 18, minute: 0, second: 0, of: day(6, 1)
        )!
        #expect(provider.isSameDay(lateEvening, assembler.batch.events[0].date))

        let toggled = assembler.toggling(day: lateEvening, using: provider)

        #expect(toggled.batch.events.isEmpty, "the occupied day was vacated, not doubled")
    }

    @Test("toggling sorts events by date")
    func toggleSorts() {
        let assembler = namedAssembler()
        let toggled = assembler
            .toggling(day: day(6, 5), using: provider)
            .toggling(day: day(6, 3), using: provider)
        let dates = toggled.batch.events.map(\.date)

        #expect(dates == dates.sorted())
    }

    // MARK: - applying

    @Test("applying onto an occupied day moves the event rather than duplicating it")
    func applyingOntoOccupiedDayMoves() {
        let assembler = namedAssembler()
        // Two distinct days occupied.
        let two = assembler
            .toggling(day: day(6, 2), using: provider)
        #expect(two.batch.events.count == 2)

        // Move the event on the 2nd onto the 3rd, as an event editor would.
        let moving = two.batch.events.first { provider.isSameDay($0.date, day(6, 2)) }!
        let applied = two.applying(moving.with(name: "Moved").with(date: day(6, 3)), using: provider)

        #expect(applied.batch.events.count == 2, "not appended: the occupied day was vacated")
        #expect(applied.batch.events.filter { provider.isSameDay($0.date, day(6, 3)) }.count == 1)
        #expect(applied.batch.events.contains { $0.name == "Moved" })
    }

    @Test("applying an event whose date changes onto a taken day still holds one per day")
    func applyingReplacingOntoTakenDay() {
        let two = namedAssembler().toggling(day: day(6, 2), using: provider)
        // The seeded event, edited to land on the day the *other* event occupies.
        let seeded = two.batch.events.first { provider.isSameDay($0.date, day(6, 1)) }!
        let applied = two.applying(seeded.with(name: "Collided").with(date: day(6, 2)), using: provider)

        #expect(applied.batch.events.count == 1, "the occupied event lost, not duplicated")
        #expect(applied.batch.events[0].name == "Collided")
    }

    @Test("applying replaces by pendingID and keeps the rest of the batch")
    func applyingReplacesByPendingID() {
        let two = namedAssembler().toggling(day: day(6, 2), using: provider)
        let seeded = two.batch.events[0]
        let applied = two.applying(seeded.with(name: "Renamed"), using: provider)

        #expect(applied.batch.events.count == 2)
        #expect(applied.batch.events.contains { $0.name == "Renamed" })
        #expect(applied.batch.events.contains { $0.pendingID == seeded.pendingID })
    }

    @Test("applying to a free day appends")
    func applyingAppends() {
        let assembler = namedAssembler()
        let fresh = CalendarEvent(name: "New", date: day(6, 9), colorName: "eventColorOption1")

        let applied = assembler.applying(fresh, using: provider)

        #expect(applied.batch.events.count == 2)
        #expect(applied.batch.events.contains { $0.name == "New" })
    }

    // MARK: - recoloring / renaming / removing

    @Test("recoloring updates the batch and every event in it")
    func recoloringPropagates() {
        let assembler = namedAssembler(color: .option1)
        let recolored = assembler.recoloring(.option3)

        #expect(recolored.batch.colorName == PCColorOption.option3.colorName)
        #expect(recolored.batch.events.allSatisfy { $0.colorName == PCColorOption.option3.colorName })
    }

    @Test("recoloring(nil) clears the colour on the batch and its events, and unsaves")
    func recoloringNilClears() {
        let recolored = namedAssembler(color: .option1).recoloring(nil)

        #expect(recolored.batch.colorName.isEmpty)
        #expect(
            recolored.batch.events.allSatisfy { $0.colorName.isEmpty },
            "stale event colours would keep painting day markers for a colour the batch no longer has"
        )
        #expect(recolored.canSave == false)
    }

    @Test("renaming changes only the name")
    func renaming() {
        let assembler = namedAssembler()
        let renamed = assembler.renaming("evening")

        #expect(renamed.batch.name == "evening")
        #expect(renamed.batch.events == assembler.batch.events)
    }

    @Test("removing an unknown event is a no-op")
    func removingUnknownIsNoOp() {
        let assembler = namedAssembler()
        let removed = assembler.removingEvent(pendingID: UUID())

        #expect(removed == assembler)
    }

    // MARK: - resolved()

    @Test("resolved returns nil once the batch is emptied")
    func resolvedNilWhenEmptied() {
        let assembler = namedAssembler()
        let emptied = assembler.removingEvent(pendingID: assembler.batch.events[0].pendingID)

        #expect(emptied.resolved() == nil)
    }

    @Test("resolved keeps the id of the row the assembly was opened from")
    func resolvedKeepsOpenedRowID() {
        let stored = CalendarEventBatch(
            persistedID: 42,
            name: "morning",
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: day(6, 1), colorName: "eventColorOption1")]
        )
        let assembler = PCEventBatchAssembleUnitOfWork.existing(stored).renaming("edited")

        let resolved = assembler.resolved()

        #expect(resolved?.persistedID == 42, "without the id a commit appends a duplicate row")
        #expect(resolved?.name == "edited")
    }

    @Test("A brand-new assembly resolves with no id, so its write appends")
    func resolvedNewHasNoID() {
        let assembler = namedAssembler()

        #expect(assembler.resolved()?.persistedID == nil)
        #expect(assembler.resolved()?.name == "morning")
    }

    @Test("resolved lets an adopted id outrank the batch's own")
    func resolvedAdoptionWins() {
        let stored = CalendarEventBatch(
            persistedID: 42,
            name: "morning",
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: day(6, 1), colorName: "eventColorOption1")]
        )
        let assembler = PCEventBatchAssembleUnitOfWork.existing(stored).adopting(persistedID: 99)

        #expect(assembler.resolved()?.persistedID == 99)
    }

    @Test("resolved returns the batch's own staged content, not the stored row's")
    func resolvedCarriesStagedEdits() {
        let stored = CalendarEventBatch(
            persistedID: 42,
            name: "morning",
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: day(6, 1), colorName: "eventColorOption1")]
        )
        let assembler = PCEventBatchAssembleUnitOfWork.existing(stored)
            .renaming("edited")
            .toggling(day: day(6, 4), using: provider)

        let resolved = assembler.resolved()

        #expect(resolved?.name == "edited")
        #expect(resolved?.events.count == 2, "staged days are what gets written")
    }

    // MARK: - Value semantics

    @Test("transformations do not mutate the receiver")
    func transformationsArePure() {
        let original = namedAssembler()
        let snapshot = original

        _ = original.renaming("other")
        _ = original.recoloring(.option4)
        _ = original.toggling(day: day(6, 8), using: provider)
        _ = original.removingEvent(pendingID: original.batch.events[0].pendingID)
        _ = original.adopting(persistedID: 5)

        #expect(original == snapshot)
        #expect(original.adoptedPersistedID == nil)
    }
}
