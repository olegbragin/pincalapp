//
//  PCCalendarModelBuilder.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 07.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// Converts the pure calendar data-source matrix (from `PCCalendarDataProvider`)
/// into the observable model tree the views consume. This is the bridge between
/// the data layer (CoreDomain) and the UI leaf (DSKit), so the models in DSKit
/// only ever see standard types.
@MainActor
enum PCCalendarModelBuilder {
    static func makeYearModel(
        from dataSource: PCCalendarYearDataSource,
        daySelectionManager: PCCalendarDaySelectionManager,
        numberOfCurrentMonth: Int,
        numberOfColumns: Int,
        columnCountResolver: @escaping (Int) -> Int
    ) -> PCCalendarYearModel {
        let model = PCCalendarYearModel(
            numberOfCurrentMonth: numberOfCurrentMonth,
            numberOfColumns: columnCountResolver(numberOfColumns)
        )
        model.months = dataSource.months.map { month in
            PCCalendarMonthModel(
                number: month.number,
                label: month.label,
                weekDaySymbols: month.weekDaySymbols,
                weeks: month.weeks.map { week in
                    PCCalendarWeekModel(
                        days: week.days.map { day in
                            PCCalendarDayModel(
                                date: day.date,
                                number: day.number,
                                isInCurrentMonth: day.isInCurrentMonth,
                                isToday: day.isToday,
                                gridMonth: month.number
                            )
                        },
                        daySelectionManager: daySelectionManager
                    )
                }
            )
        }
        return model
    }
}
