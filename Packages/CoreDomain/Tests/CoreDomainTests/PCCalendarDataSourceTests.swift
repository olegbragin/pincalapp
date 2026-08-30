import Foundation
import Testing
import CoreDomain

@Suite("Calendar Data Source Models Tests")
struct PCCalendarDataSourceTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    @Test("Day data source stores its values")
    func dayDataSource() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!

        let day = PCCalendarDayDataSource(date: date, number: 5, isInCurrentMonth: true, isToday: false)

        #expect(day.date == date)
        #expect(day.number == 5)
        #expect(day.isInCurrentMonth)
        #expect(!day.isToday)
    }

    @Test("Week data source groups days in order")
    func weekDataSource() {
        let days = (1...7).map { i in
            PCCalendarDayDataSource(
                date: Date(timeIntervalSince1970: TimeInterval(i) * 86400),
                number: i,
                isInCurrentMonth: true,
                isToday: false
            )
        }

        let week = PCCalendarWeekDataSource(number: 12, days: days)

        #expect(week.number == 12)
        #expect(week.days.count == 7)
        #expect(week.days.map(\.number) == (1...7).map { $0 })
    }

    @Test("Month data source stores number, label, symbols and weeks")
    func monthDataSource() {
        let week = PCCalendarWeekDataSource(number: 1, days: [])

        let month = PCCalendarMonthDataSource(
            number: 3,
            label: "March",
            weekDaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
            weeks: [week]
        )

        #expect(month.number == 3)
        #expect(month.label == "March")
        #expect(month.weekDaySymbols.count == 7)
        #expect(month.weeks.count == 1)
        #expect(month.weeks.first?.number == week.number)
        #expect(month.weeks.first?.days.isEmpty == true)
    }

    @Test("Day data source equality matches field-by-field values")
    func dayDataSourceEquals() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let a = PCCalendarDayDataSource(date: date, number: 1, isInCurrentMonth: true, isToday: false)
        let b = PCCalendarDayDataSource(date: date, number: 1, isInCurrentMonth: true, isToday: false)
        let c = PCCalendarDayDataSource(date: date, number: 2, isInCurrentMonth: true, isToday: false)

        #expect(a.date == b.date && a.number == b.number && a.isInCurrentMonth == b.isInCurrentMonth && a.isToday == b.isToday)
        #expect(c.number != a.number)
    }
}