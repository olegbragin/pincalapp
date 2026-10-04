
import Foundation
import Testing
import DSKit

@Suite("PCCalendarDaySelectionManager Tests")
@MainActor
struct PCCalendarDaySelectionManagerTests {
    private func dayModel(_ dayOfMonth: Int, inCurrentMonth: Bool = true) -> PCCalendarDayModel {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = dayOfMonth
        components.hour = 12
        return PCCalendarDayModel(
            date: Calendar(identifier: .gregorian).date(from: components)!,
            number: dayOfMonth,
            isInCurrentMonth: inCurrentMonth,
            isToday: false,
            gridMonth: 6
        )
    }

    @Test("A tap is reported to the listener, and the selection still happens")
    func tapIsReported() {
        let manager = PCCalendarDaySelectionManager()
        var tapped: [Date] = []
        manager.onDayTapped = { tapped.append($0) }

        manager.select(day: dayModel(4))

        #expect(tapped.count == 1)
        #expect(manager.selectedDays.count == 1, "the presentational set still tracks the tap")
    }

    @Test("Exactly one listener is called, so two screens cannot both act on a tap")
    func onlyTheInstalledListenerIsCalled() {
        let manager = PCCalendarDaySelectionManager()
        var first = 0
        var second = 0
        manager.onDayTapped = { _ in first += 1 }
        manager.onDayTapped = { _ in second += 1 } // replaces, not adds

        manager.select(day: dayModel(4))

        #expect(first == 0, "the replaced listener must not fire")
        #expect(second == 1)
    }

    @Test("Clearing the listener on disappear stops the screen hearing anything")
    func clearingTheListenerStopsCallbacks() {
        let manager = PCCalendarDaySelectionManager()
        var taps = 0
        manager.onDayTapped = { _ in taps += 1 }

        manager.select(day: dayModel(4))
        manager.onDayTapped = nil
        manager.select(day: dayModel(5))

        #expect(taps == 1, "only the tap that happened while the screen was visible")
    }

    @Test("A day outside the current month is not a tap at all")
    func adjacentMonthCellsAreNotTaps() {
        let manager = PCCalendarDaySelectionManager()
        var taps = 0
        manager.onDayTapped = { _ in taps += 1 }

        manager.select(day: dayModel(4, inCurrentMonth: false))

        #expect(taps == 0)
        #expect(manager.selectedDays.isEmpty)
    }

    @Test("No listener is required — selection works with nobody listening")
    func selectionWorksWithoutAListener() {
        let manager = PCCalendarDaySelectionManager()
        manager.select(day: dayModel(4))
        #expect(manager.selectedDays.count == 1)
    }
}

@Suite("PCColorOption Tests")
struct PCColorOptionTests {
    @Test("Cases are equatable and hashable, so a colour can live in an Equatable state")
    func casesAreEquatableAndHashable() {
        #expect(PCColorOption.option1 == .option1)
        #expect(PCColorOption.option1 != .option2)

        let set: Set<PCColorOption> = [.option1, .option2, .option1]
        #expect(set.count == 2, "duplicates collapse, which is what a value type buys")
        #expect(set.contains(.option2))
    }

    @Test("Every case round-trips through its stored name")
    func roundTripsThroughName() {
        for option in PCColorOption.allCases {
            #expect(PCColorOption(option.colorName) == option, "\(option.colorName)")
        }
    }

    @Test("Colour names stay distinct")
    func namesAreDistinct() {
        let names = PCColorOption.allCases.map(\.colorName)
        #expect(Set(names).count == names.count, "\(names)")
    }
}
