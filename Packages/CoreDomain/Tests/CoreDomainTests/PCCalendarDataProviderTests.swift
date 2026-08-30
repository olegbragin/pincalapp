import Foundation
import Testing
import CoreDomain

@Suite("PCCalendarDataProvider Tests")
struct PCCalendarDataProviderTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    @Test("Returns exactly 12 months for the year, numbered 1...12")
    func returnsTwelveMonths() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        let months = provider.months(forYear: 2026)

        #expect(months.count == 12)
        for (index, month) in months.enumerated() {
            #expect(month.number == index + 1)
            #expect(month.label == calendar.standaloneMonthSymbols[index])
        }
    }

    @Test("Weekday symbols are ordered starting from the calendar first weekday")
    func weekdaySymbolsStartFromFirstWeekday() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        let symbols = provider.months(forYear: 2026)[0].weekDaySymbols

        #expect(symbols.count == 7)
        #expect(symbols.first == calendar.veryShortStandaloneWeekdaySymbols[calendar.firstWeekday - 1])
    }

    @Test("Every month expands to 6 weeks of 7 consecutive days")
    func sixWeeksOfConsecutiveDays() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        for year in [2026, 2027, 2028] {
            for month in provider.months(forYear: year) {
                #expect(month.weeks.count == 6)
                for week in month.weeks {
                    #expect(week.days.count == 7)
                }

                let days = month.weeks.flatMap(\.days)
                #expect(days.count == 42)
                for i in 0..<(days.count - 1) {
                    let next = calendar.date(byAdding: .day, value: 1, to: days[i].date)
                    #expect(days[i + 1].date == next)
                }
            }
        }
    }

    @Test("Every week starts on the calendar first weekday")
    func weeksStartOnFirstWeekday() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        for month in provider.months(forYear: 2026) {
            for week in month.weeks {
                let weekday = calendar.component(.weekday, from: week.days.first!.date)
                #expect(weekday == calendar.firstWeekday)
            }
        }
    }

    @Test("Days marked as in current month match the month length")
    func inCurrentMonthMatchesMonthLength() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        for year in [2026, 2027, 2028] {
            for month in provider.months(forYear: year) {
                let monthLength = calendar.range(of: .day, in: .month, for: day(year, month.number, 1))!.count
                let inMonthDays = month.weeks.flatMap(\.days).filter(\.isInCurrentMonth)
                #expect(inMonthDays.count == monthLength)
            }
        }
    }

    @Test("Leap year February contains 29 in-month days")
    func leapYearFebruary() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        let february = provider.months(forYear: 2028).first { $0.number == 2 }!

        #expect(february.weeks.flatMap(\.days).filter(\.isInCurrentMonth).count == 29)
    }

    @Test("Today flags only appear for in-current-month days")
    func todayOnlyForInMonthDays() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        for month in provider.months(forYear: 2026) {
            for calendarDay in month.weeks.flatMap(\.days) {
                if calendarDay.isToday {
                    #expect(calendarDay.isInCurrentMonth)
                }
            }
        }
    }

    @Test("Day numbers match the calendar day component")
    func dayNumbersMatchComponents() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        for month in provider.months(forYear: 2026) {
            for calendarDay in month.weeks.flatMap(\.days) {
                #expect(calendarDay.number == calendar.component(.day, from: calendarDay.date))
            }
        }
    }

    @Test("Current month number is within valid range")
    func numberOfCurrentMonthIsInRange() {
        let provider = PCCalendarDataProvider(calendar: calendar)

        #expect((1...12).contains(provider.numberOfCurrentMonth))
    }

    @Test("dateComponents describes the same instant")
    func dateComponentsRoundTrip() {
        let provider = PCCalendarDataProvider(calendar: calendar)
        let date = day(2026, 3, 15)

        let components = provider.dateComponents(forDate: date)

        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 15)
        #expect(components.date == date)
    }
}