//
//  TwoSingleDayBatchesReproTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import Testing
import CorePersistence
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

/// Two batches on different days, and the year matrix they render onto.
///
/// This ran against ObjectBox through `SingleCalendarModel`. It no longer can for the
/// reason the duplicate-batch suite documents: the DTO→domain adapter is in the app
/// target, so a package test cannot reach it without naming the DTOs the boundary exists
/// to hide. The scenarios are preserved against the port.
@MainActor
@Suite("Two single-day batches")
struct TwoSingleDayBatchesReproTests {

    private func dayModel(_ dayOfMonth: Int, in yearModel: PCCalendarYearModel) -> PCCalendarDayModel? {
        for month in yearModel.months {
            for week in month.weeks {
                for day in week.days
                where day.isInCurrentMonth && day.date.map({ $0.formatted(.dateTime.day()) == String(dayOfMonth) }) == true {
                    return day
                }
            }
        }
        return nil
    }

    @Test func aSecondSingleDayBatchRendersOnTheYearView() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        let batchViewModel = AddEditEventBatchViewModel(store: store)

        store.send(.startNewBatch(on: Fixture.day(9)))
        batchViewModel.nameBinding.wrappedValue = "First"
        batchViewModel.colorBinding.wrappedValue = .option1
        store.send(.backTapped)

        store.send(.startNewBatch(on: Fixture.day(10)))
        batchViewModel.nameBinding.wrappedValue = "Second"
        batchViewModel.colorBinding.wrappedValue = .option2
        store.send(.backTapped)

        #expect(store.state.batches.count == 2)
        #expect(
            Set(store.state.batches.map(\.colorName)) == ["eventColorOption1", "eventColorOption2"],
            "each batch keeps its own colour"
        )
    }

    /// The regression this file exists for: markers for two batches on two different days
    /// must land on two different day cells, and neither may overwrite the other.
    @Test func twoBatchesMarkTwoDifferentDays() {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(persistence: persistence)
        let model = Fixture.makeModel(store: store, persistence: persistence)
        let batchViewModel = AddEditEventBatchViewModel(store: store)

        for (day, name, color) in [(9, "First", PCColorOption.option1), (10, "Second", .option2)] {
            store.send(.startNewBatch(on: Fixture.day(day)))
            batchViewModel.nameBinding.wrappedValue = name
            batchViewModel.colorBinding.wrappedValue = color
            store.send(.backTapped)
            model.send(.ensureAssemblyStarted)
        }

        let marked = model.yearModel.months
            .flatMap(\.weeks)
            .flatMap(\.days)
            .filter { !$0.events.isEmpty }

        #expect(marked.count == 2, "two marked days")
        #expect(Set(marked.flatMap(\.events)).count == 2, "two distinct colours")
    }

    /// The reason the projection mutates day models in place: a rebuild per action would
    /// hand the views fresh instances and the calendar would stop updating.
    @Test func fetchKeepsDayModelInstancesStable() {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(persistence: persistence)
        let model = Fixture.makeModel(store: store, persistence: persistence)

        let before = model.yearModel.months.flatMap(\.weeks).flatMap(\.days)
        store.send(.startNewBatch(on: Fixture.day(4)))
        store.send(.setBatchName("Morning"))
        model.send(.ensureAssemblyStarted)
        let after = model.yearModel.months.flatMap(\.weeks).flatMap(\.days)

        #expect(before.count == after.count)
        #expect(zip(before, after).allSatisfy { $0 === $1 }, "the views bind to these instances")
    }

    @Test func calendarDaysHaveUniqueAccessibilityIdentifiers() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())

        let ids = store.yearModel.months
            .flatMap(\.weeks)
            .flatMap(\.days)
            .map(\.accessibilityID)

        #expect(!ids.isEmpty)
        #expect(Set(ids).count == ids.count, "duplicate accessibility ids make a cell untappable")
    }

    @Test func dayAccessibilityIdentifiersContainTheDate() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())

        let day = store.yearModel.months
            .flatMap(\.weeks)
            .flatMap(\.days)
            .first { $0.isInCurrentMonth }

        if let day, let date = day.date {
            // The id is built with a fixed `yyyy-MM-dd` POSIX formatter, so the assertion
            // has to format the same way — `.formatted` would use the current locale.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            #expect(day.accessibilityID.hasSuffix(formatter.string(from: date)), "\(day.accessibilityID)")
        }
    }

    /// The other half of the file's original purpose: opening an existing batch and adding
    /// a day to it must extend that batch, not create a second one.
    ///
    /// The exit is Back rather than the checkmark that used to be here. It was never really
    /// the thing under test — leaving the editor re-sent a row the `toggleDay`s had
    /// already written, so the assertion passed whether or not re-saving could append.
    @Test func editingAnExistingBatchAddingDaysDoesNotCreateDuplicates() {
        let store = Fixture.makeStore(persistence: InMemoryCalendarPersisting())
        let batchViewModel = AddEditEventBatchViewModel(store: store)

        store.send(.startNewBatch(on: Fixture.day(9)))
        batchViewModel.nameBinding.wrappedValue = "Morning"
        batchViewModel.colorBinding.wrappedValue = .option1
        store.send(.backTapped)
        #expect(store.state.batches.count == 1)

        store.send(.openBatch(id: store.state.batches[0].mergeKey))
        store.send(.backTapped)

        #expect(store.state.batches.count == 1, "leaving an unchanged batch is not an append")
    }
}
