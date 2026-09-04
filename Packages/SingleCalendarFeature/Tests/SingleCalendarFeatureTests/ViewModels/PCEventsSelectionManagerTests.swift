import Foundation
import Testing
import CorePersistence
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("PCEventsSelectionManager Tests")
struct PCEventsSelectionManagerTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func event(_ name: String = "Event", day dayOfMonth: Int, color: String = "eventColorOption1") -> EventDataSource {
        .init(name: name, date: day(2026, 6, dayOfMonth), color: color)
    }

    @Test("prepare sorts and stamps missing timestamps")
    func prepareSortsAndStamps() {
        let m = PCEventsSelectionManager()
        m.prepare(with: [event("B", day: 2), event("A", day: 1)])

        #expect(m.events.map(\.name) == ["A", "B"])
        #expect(m.events.allSatisfy { $0.timestamp != nil })
    }

    @Test("hasEvent reports a same-day event")
    func hasEvent() {
        let m = PCEventsSelectionManager(events: [event(day: 1)])
        #expect(m.hasEvent(on: day(2026, 6, 1)))
        #expect(!m.hasEvent(on: day(2026, 6, 2)))
    }

    @Test("addEvent stamps a timestamp and keeps sorting")
    func addEvent() {
        let m = PCEventsSelectionManager()
        m.addEvent(event("Later", day: 2))
        m.addEvent(event("Earlier", day: 1))

        #expect(m.events.map(\.name) == ["Earlier", "Later"])
        #expect(m.events[0].timestamp != nil)
    }

    @Test("removeEvent removes all events on the same day")
    func removeEvent() {
        let m = PCEventsSelectionManager(events: [event(day: 1), event(day: 2)])
        m.removeEvent(on: day(2026, 6, 1))

        #expect(m.events.map(\.name) == ["Event"])
    }

    @Test("removeEvents removes by index and notifies")
    func removeEvents() {
        var changes = 0
        let m = PCEventsSelectionManager(events: [event(day: 1), event(day: 2), event(day: 3)])
        m.onEventsChanged = { changes += 1 }

        m.removeEvents(at: [0, 2])

        #expect(m.events.map(\.name) == ["Event"])
        #expect(changes == 1)
    }

    @Test("apply replaces by timestamp, else by id, else appends")
    func apply() {
        let ts = UUID()
        let a = EventDataSource(id: 1, name: "A", date: day(2026, 6, 1), color: "eventColorOption1", timestamp: ts)
        let m = PCEventsSelectionManager(events: [a])

        // Timestamp match replaces.
        m.apply(EventDataSource(id: 9, name: "A2", date: day(2026, 6, 1), color: "eventColorOption2", timestamp: ts))
        #expect(m.events.count == 1)
        #expect(m.events[0].name == "A2")
        #expect(m.events[0].color == "eventColorOption2")

        // Same id, different timestamp replaces by id.
        let b = EventDataSource(id: 2, name: "B", date: day(2026, 6, 2), color: "eventColorOption1", timestamp: UUID())
        m.addEvent(b)
        let bUpdated = EventDataSource(id: 2, name: "B2", date: day(2026, 6, 3), color: "eventColorOption3", timestamp: UUID())
        m.apply(bUpdated)
        #expect(m.events.count == 2)
        #expect(m.events.map(\.name).contains("B2"))

        // No match appends.
        m.apply(EventDataSource(id: 0, name: "New", date: day(2026, 6, 4), color: "eventColorOption1"))
        #expect(m.events.count == 3)
    }

    @Test("apply notifies")
    func applyNotifies() {
        var changes = 0
        let m = PCEventsSelectionManager()
        m.onEventsChanged = { changes += 1 }
        m.apply(event(day: 1))
        #expect(changes == 1)
    }

    @Test("recolorAll recolors every event")
    func recolorAll() {
        let m = PCEventsSelectionManager(events: [event(day: 1), event(day: 2)])
        m.recolorAll(to: "eventColorOption4")
        #expect(m.events.allSatisfy { $0.color == "eventColorOption4" })
    }

    @Test("reset clears events")
    func reset() {
        let m = PCEventsSelectionManager(events: [event(day: 1)])
        m.reset()
        #expect(m.events.isEmpty)
    }
}
