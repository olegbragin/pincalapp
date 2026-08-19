//
//  PCCalendarYearModelTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 14.08.2026.
//

import Testing
import Foundation
@testable import PinCalApp

@MainActor
struct PCCalendarYearModelTests {

    @Test func setInitialNumberOfColumnsSyncsBothProperties() {
        let model = PCCalendarYearModel()

        model.set(initialNumberOfColumns: 5)

        #expect(model.numberOfColumns == 5)
        #expect(model.internalNumberOfColumns == 5)
    }

    @Test func maximumNumberOfColumnsClampsCurrentColumns() {
        let model = PCCalendarYearModel()
        model.set(initialNumberOfColumns: 5)

        model.maximumNumberOfColumns = 4

        #expect(model.numberOfColumns == 4)
        #expect(model.internalNumberOfColumns == 4)
    }

    @Test func raisingMaximumNumberOfColumnsPreservesCurrentColumns() {
        let model = PCCalendarYearModel()
        model.set(initialNumberOfColumns: 3)

        model.maximumNumberOfColumns = 6

        #expect(model.numberOfColumns == 3)
        #expect(model.internalNumberOfColumns == 3)
    }

    @Test func pinchModelClampsToMaximumOnZoomOut() {
        let model = PCCalendarPinchToZoomGestureModel(numberOfColumns: 2, maxNumberOfColumns: 2)
        var reportedChanges: [Int] = []

        model.handleMagnify(
            magnification: 0.5,
            velocity: 0,
            gestureDuration: 0.3,
            didChange: { reportedChanges.append($0) }
        )

        #expect(model.numberOfColumns == 2)
        #expect(reportedChanges.isEmpty)
    }

    @Test func pinchModelIncreasesColumnsUpToMaximum() {
        let model = PCCalendarPinchToZoomGestureModel(numberOfColumns: 2, maxNumberOfColumns: 3)
        var reportedChanges: [Int] = []

        model.handleMagnify(
            magnification: 0.5,
            velocity: 0,
            gestureDuration: 0.3,
            didChange: { reportedChanges.append($0) }
        )

        #expect(model.numberOfColumns == 3)
        #expect(reportedChanges == [3])

        model.handleMagnify(
            magnification: 0.5,
            velocity: 0,
            gestureDuration: 0.3,
            didChange: { reportedChanges.append($0) }
        )

        #expect(model.numberOfColumns == 3)
    }

    @Test func updateMaxNumberOfColumnsReclampsCurrentValue() {
        let model = PCCalendarPinchToZoomGestureModel(numberOfColumns: 5, maxNumberOfColumns: 6)

        model.updateMaxNumberOfColumns(4)

        #expect(model.maxNumberOfColumns == 4)
        #expect(model.numberOfColumns == 4)
    }
}
