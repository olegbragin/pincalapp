//
//  BatchEditorCalendarScopeTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 04.10.2026.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// The batch editor's calendar marks the batch being edited, and nothing else.
///
/// Reported as: tap an empty day, add two more days in the editor, leave, tap another
/// empty day — and the editor came up with all four days marked.
///
/// It was never the assembly being reused, which is the reading the report started from.
/// `state.assembly` was a brand-new one-day batch and the editor's *event list* agreed —
/// that list reads `assembly.batch.events` and nothing else. What was wrong is one layer
/// up: the editor's calendar was painted from `state.dayEventColors`, which describes the
/// whole calendar, committed rows and all. So the other batch's days were drawn in the
/// editor, and worse, they *looked* like this batch's: a marked day belonging to another
/// batch is added to this one when tapped, not removed from it, because `toggling` only
/// knows about the batch it is toggling.
///
/// So the marker payload is not one thing. The main panel's is the calendar's; the editor's
/// is one batch's, and sharing a single payload between them is what put a stranger's days
/// under the user's finger.
@MainActor
@Suite("The batch editor's calendar shows only the batch being edited")
struct BatchEditorCalendarScopeTests {

    private func day(_ dayOfMonth: Int) -> Date { Fixture.day(dayOfMonth) }

    /// The number of every marked day cell, ascending.
    ///
    /// Read off `PCCalendarDayModel.text` rather than recomputed from `date`: the cell was
    /// built in the provider's time zone while the fixture dates are UTC instants, and
    /// extracting the day back off the instant slides it by one wherever the two disagree.
    /// `text` is the number the cell actually shows, so there is nothing left to disagree
    /// about.
    ///
    /// `PCCalendarMarkerProjector.apply` only writes to `isInCurrentMonth` cells, so a
    /// trailing day of one month appearing at the head of the next grid is never marked and
    /// cannot be counted twice.
    private func markedDays(in yearModel: PCCalendarYearModel) -> [Int] {
        yearModel.months
            .flatMap(\.weeks)
            .flatMap(\.days)
            .filter { !$0.events.isEmpty }
            .compactMap { Int($0.text) }
            .sorted()
    }

    /// The whole reported flow, through the store.
    @Test("A new batch marks its own day, not the days of the batch made before it")
    func newBatchMarksOnlyItsOwnDays() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())

        // 1–3: tap an empty day, then widen that batch from the editor's calendar.
        store.send(.dayTappedInCalendar(day(2)))
        store.send(.toggleDay(day(3)))
        store.send(.toggleDay(day(4)))
        // 4: leave. One Back is enough: tapping an empty day pushed the editor onto an
        // empty stack, so there is no day list beneath it to pop back to.
        store.send(.backTapped)

        // 5: another empty day, so this batch shares nothing with the one above.
        store.send(.dayTappedInCalendar(day(10)))

        #expect(
            store.state.assembly?.batch.events.count == 1,
            "precondition: the assembly is a new one-day batch, which is what the report doubted"
        )
        #expect(
            markedDays(in: store.yearModel) == [10],
            "the editor's calendar belongs to the batch being edited"
        )
    }

    /// The same scope from the other entry point. Opened from the day list, the editor is
    /// editing a row that already has days — and must not borrow a neighbour's.
    ///
    /// `openBatch` is dispatched directly rather than reached by tapping a card, because what
    /// is under test is the scope of the editor's calendar and the card does nothing else.
    @Test("An opened batch marks its own days and no other batch's")
    func openedBatchMarksOnlyItsOwnDays() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())

        store.send(.startNewBatch(on: day(2)))
        store.send(.toggleDay(day(3)))
        store.send(.backTapped)
        store.send(.startNewBatch(on: day(20)))
        store.send(.backTapped)

        let opened = store.state.batches.first {
            $0.occurs(on: day(2), using: store.state.dataProvider)
        }
        #expect(opened != nil, "precondition: the 2nd still holds a batch")
        guard let opened else { return }
        store.send(.openBatch(id: opened.mergeKey))

        #expect(markedDays(in: store.yearModel) == [2, 3])
    }

    /// Scoping the editor's payload must not scope the main panel's.
    ///
    /// The main calendar is the one place that is supposed to describe every batch, and it
    /// reads its own payload. A fix that narrowed the shared one would leave the calendar
    /// claiming a day is empty while the day list has a card on it.
    @Test("The main calendar still marks every batch's days")
    func mainCalendarKeepsMarkingEveryBatch() {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(persistence: persistence)
        let model = Fixture.makeModel(store: store, persistence: persistence)

        store.send(.startNewBatch(on: day(2)))
        store.send(.toggleDay(day(3)))
        store.send(.backTapped)
        store.send(.startNewBatch(on: day(20)))
        store.send(.backTapped)
        model.send(.ensureAssemblyStarted)

        #expect(markedDays(in: model.yearModel) == [2, 3, 20])
    }
}