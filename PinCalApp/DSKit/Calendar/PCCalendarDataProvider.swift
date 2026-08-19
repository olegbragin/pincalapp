//
//  USCalendarProvider.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 23.03.2026.
//

import Foundation

struct USCalendarDataProvider {
    private var calendar: Calendar
    
    var numberOfCurrentMonth: Int {
        calendar.component(.month, from: Date())
    }
    
    init(
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        self.calendar.timeZone = .current
        self.calendar.locale = .current
    }
    
    func months(forYear year: Int) -> [USCalendarMonthDataSource] {
        (0...11).map {
            let monthNumber = $0 + 1
            return USCalendarMonthDataSource(
                number: monthNumber,
                label: calendar.standaloneMonthSymbols[$0],
                weekDaySymbols: orderedWeekdaySymbols,
                weeks: weeks(forMonth: monthNumber, ofYear: year)
            )
        }
    }
    
    func dateComponents(forDate date: Date) -> DateComponents {
        calendar.dateComponents(in: calendar.timeZone, from: date)
    }

    private func weeks(
        forMonth month: Int,
        ofYear year: Int
    ) -> [USCalendarWeekDataSource] {
        let todayDate = Date()
        
        // 1. Первый день заданного месяца
        var components = DateComponents(year: year, month: month, day: 1)
        guard let startOfMonth = calendar.date(from: components) else { return [] }
        
        // 2. Начало первой полной недели (может быть в предыдущем месяце)
        let startOfFirstWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startOfMonth))!
        
        // 3. Конец последней полной недели (может быть в следующем месяце)
        let endOfMonth = calendar.range(of: .day, in: .month, for: startOfMonth)!.count
        components.day = endOfMonth
        guard
            let lastDayOfMonth = calendar.date(from: components),
            let endOfLastWeek = date(byEndingOf: .weekOfYear, for: lastDayOfMonth)
        else { return [] }
        
        // 4. Генерируем все даты от startOfFirstWeek до endOfLastWeek
        var dates: [Date] = []
        var currentDate = startOfFirstWeek
        
        while currentDate <= endOfLastWeek {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        // 5. Группируем по неделям
        var weeks: [USCalendarWeekDataSource] = []
        var currentWeek: [USCalendarDayDataSource] = []
        
        for date in dates {
            let weekday = calendar.component(.weekday, from: date)
            let isFirstDayOfWeek = weekday == calendar.firstWeekday
            
            if isFirstDayOfWeek && !currentWeek.isEmpty {
                let weekNumber = calendar.component(.weekOfYear, from: date)
                weeks.append(
                    USCalendarWeekDataSource(
                        number: weekNumber,
                        days: currentWeek
                    )
                )
                currentWeek = []
            }
            
            // Преобразуем дату в Day
            let dayNumberOfDate = calendar.component(.day, from: date)
            let monthOfDate = calendar.component(.month, from: date)
            let yearOfDate = calendar.component(.year, from: date)
            let isInMonth = (month == monthOfDate) && (year == yearOfDate)
            
            currentWeek.append(
                USCalendarDayDataSource(
                    date: date,
                    number: dayNumberOfDate,
                    isInCurrentMonth: isInMonth,
                    isToday: calendar.isDate(date, inSameDayAs: todayDate) && isInMonth
                )
            )
        }
        
        if !currentWeek.isEmpty {
            let weekNumber = calendar.component(.weekOfYear, from: todayDate)
            weeks.append(
                USCalendarWeekDataSource(
                    number: weekNumber,
                    days: currentWeek
                )
            )
        }
        
        // 6. Если недель меньше 6 — дополняем следующими неделями
        while weeks.count < 6 {
            // Берём последний день последней недели
            guard let lastDate = weeks.last?.days.last?.date else { break }
            
            // Генерируем следующую неделю (7 дней после lastDate)
            var nextWeekDates: [Date] = []
            var nextDate = calendar.date(byAdding: .day, value: 1, to: lastDate)!
            for _ in 0..<7 {
                nextWeekDates.append(nextDate)
                guard let futureDate = calendar.date(byAdding: .day, value: 1, to: nextDate) else { break }
                nextDate = futureDate
            }
            
            // Преобразуем даты в Day
            let nextWeekDays = nextWeekDates.map { date in
                let dayNumberOfDate = calendar.component(.day, from: date)
                let monthOfDate = calendar.component(.month, from: date)
                let yearOfDate = calendar.component(.year, from: date)
                let isInMonth = (month == monthOfDate) && (year == yearOfDate)
                return USCalendarDayDataSource(
                    date: date,
                    number: dayNumberOfDate,
                    isInCurrentMonth: isInMonth,
                    isToday: calendar.isDate(date, inSameDayAs: todayDate) && isInMonth
                )
            }
            
            let weekNumber = calendar.component(.weekOfYear, from: nextDate)
            weeks.append(
                USCalendarWeekDataSource(
                    number: weekNumber,
                    days: nextWeekDays
                )
            )
        }
        
        return weeks
    }
    
    private func date(byEndingOf component: Calendar.Component, for date: Date) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        
        switch component {
        case .weekOfYear:
            // Находим начало недели, затем добавляем 6 дней и 23:59:59
            if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) {
                var endComps = DateComponents()
                endComps.day = 6
                endComps.hour = 23
                endComps.minute = 59
                endComps.second = 59
                return calendar.date(byAdding: endComps, to: startOfWeek)
            }
            return nil
            
        case .month:
            comps.day = calendar.range(of: .day, in: .month, for: date)?.count
            comps.hour = 23
            comps.minute = 59
            comps.second = 59
            return calendar.date(from: comps)
            
        case .day:
            comps.hour = 23
            comps.minute = 59
            comps.second = 59
            return calendar.date(from: comps)
            
        default:
            return nil
        }
    }
    
    private var orderedWeekdaySymbols: [String] {
        let allSymbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(allSymbols[shift...] + allSymbols[..<shift])
    }
}
