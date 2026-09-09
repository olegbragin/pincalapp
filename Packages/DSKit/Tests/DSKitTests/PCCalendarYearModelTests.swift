//
//  PCCalendarYearModelTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 14.08.2026.
//

import Testing
import Foundation
import DSKit

@MainActor
struct PCCalendarYearModelTests {

    @Test func settingNumberOfColumnsPersistsTheValue() {
        let model = PCCalendarYearModel()

        model.numberOfColumns = 5

        #expect(model.numberOfColumns == 5)
    }

    @Test func initKeepsNumberOfColumns() {
        let model = PCCalendarYearModel(numberOfColumns: 5)

        #expect(model.numberOfColumns == 5)
    }

    @Test func maximumNumberOfColumnsClampsCurrentColumns() {
        let model = PCCalendarYearModel()
        model.numberOfColumns = 5

        model.maximumNumberOfColumns = 4

        #expect(model.numberOfColumns == 4)
    }

    @Test func raisingMaximumNumberOfColumnsPreservesCurrentColumns() {
        let model = PCCalendarYearModel()
        model.numberOfColumns = 3

        model.maximumNumberOfColumns = 6

        #expect(model.numberOfColumns == 3)
    }

    @Test func pinchModelClampsToMaximumOnZoomOut() {
        let model = PCPinchToZoomGestureModel()
        var zoomInCount = 0
        var zoomOutCount = 0
        model.onPinchedToZoomIn = { zoomInCount += 1 }
        model.onPinchedToZoomOut = { zoomOutCount += 1 }

        model.handleMagnify(
            magnification: 0.5,
            velocity: 0,
            gestureDuration: 0.3
        )

        #expect(zoomInCount == 1)
        #expect(zoomOutCount == 0)
    }

    @Test func pinchModelFiresZoomOutOnPinchIn() {
        let model = PCPinchToZoomGestureModel()
        var zoomInCount = 0
        var zoomOutCount = 0
        model.onPinchedToZoomIn = { zoomInCount += 1 }
        model.onPinchedToZoomOut = { zoomOutCount += 1 }

        model.handleMagnify(
            magnification: 0.5,
            velocity: 0,
            gestureDuration: 0.3
        )

        #expect(zoomInCount == 1)

        model.handleMagnify(
            magnification: 0.5,
            velocity: 0,
            gestureDuration: 0.3
        )

        #expect(zoomInCount == 1)
    }

    @Test func pinchModelFiresZoomInOnPinchOut() {
        let model = PCPinchToZoomGestureModel()
        var zoomInCount = 0
        var zoomOutCount = 0
        model.onPinchedToZoomIn = { zoomInCount += 1 }
        model.onPinchedToZoomOut = { zoomOutCount += 1 }

        model.handleMagnify(
            magnification: 2.0,
            velocity: 0,
            gestureDuration: 0.3
        )

        #expect(zoomOutCount == 1)
        #expect(zoomInCount == 0)
    }
}
