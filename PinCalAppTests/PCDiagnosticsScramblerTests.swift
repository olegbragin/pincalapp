//
//  PCDiagnosticsScramblerTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import Testing
import CorePersistence
@testable import PinCalApp

/// The scrambler.
///
/// Every test here is about **what does not leak**, so they are written as "this text must not
/// contain X" rather than "this text equals Y" wherever they can be. An equality assertion can be
/// satisfied by a scrubber that happens to be right about one string; an absence assertion fails
/// for any scrubber that is wrong about any of them.
@Suite("PCDiagnosticsScrambler")
struct PCDiagnosticsScramblerTests {
    private func scrubber(_ names: [PCDiagnosticsName]) -> PCDiagnosticsScrambler {
        PCDiagnosticsScrambler(names: names)
    }

    @Test("A calendar name is removed from a message")
    func removesCalendarName() {
        let s = scrubber([.calendar("Therapy notes")])

        let out = s.scrub("Couldn't save Therapy notes")

        #expect(!out.contains("Therapy"))
        #expect(!out.contains("notes"))
        #expect(out.contains("<calendar-1>"))
    }

    @Test("Batch and event names are removed too")
    func removesBatchAndEventNames() {
        let s = scrubber([
            .calendar("Work"),
            .batch("Standup"),
            .event("Dentist"),
        ])

        let out = s.scrub("Work/Standup: Dentist failed")

        #expect(!out.contains("Work"))
        #expect(!out.contains("Standup"))
        #expect(!out.contains("Dentist"))
    }

    /// The failure mode that makes a naive implementation unsafe rather than merely wrong: a short
    /// name that is a prefix of a longer one gets consumed first, leaving the tail behind. That
    /// tail *is* part of the name, so this is a partial leak and not just ugly output.
    @Test("A name that is a prefix of a longer one is fully removed")
    func prefixDoesNotLeakTail() {
        let s = scrubber([.calendar("Work"), .calendar("Workout plan")])

        let out = s.scrub("failed on Workout plan")

        #expect(!out.contains("Workout"))
        #expect(!out.contains(" plan"))
    }

    @Test("The same name always maps to the same token")
    func stableAcrossTheExport() {
        let s = scrubber([.calendar("Work"), .batch("Work")])

        // Same value in two kinds is one token: the text is the same text, and reporting it as
        // two things would imply a distinction that was never there.
        let out = s.scrub("Work then Work again")

        #expect(out.components(separatedBy: "<calendar-1>").count == 3)
    }

    @Test("Tokens keep the kind, so rows can still be told apart")
    func tokensAreTyped() {
        let s = scrubber([.calendar("A"), .batch("B"), .event("C")])

        let out = s.scrub("A B C")

        #expect(out.contains("<calendar-1>"))
        #expect(out.contains("<batch-1>"))
        #expect(out.contains("<event-1>"))
    }

    /// Numbering must not depend on the order the database happened to be walked in, or two
    /// exports of the same data would be impossible to compare.
    @Test("Numbering does not depend on input order")
    func numberingIsOrderIndependent() {
        let forward = scrubber([.calendar("Alpha"), .calendar("Beta"), .calendar("Gamma")])
        let backward = scrubber([.calendar("Gamma"), .calendar("Beta"), .calendar("Alpha")])

        #expect(forward.scrub("Alpha") == backward.scrub("Alpha"))
        #expect(forward.scrub("Beta") == backward.scrub("Beta"))
    }

    @Test("An empty name list leaves text alone")
    func emptyNamesIsIdentity() {
        let s = scrubber([])

        #expect(s.scrub("nothing to redact here") == "nothing to redact here")
        #expect(s.redactionCount == 0)
    }

    /// Whitespace-only names are what a default `"New event"` template or an emptied field
    /// produces. Scrubbing them would replace every space in every message.
    @Test("Blank names are not treated as names")
    func ignoresBlankNames() {
        let s = scrubber([.calendar(""), .batch("   ")])

        #expect(s.redactionCount == 0)
        #expect(s.scrub("two words apart") == "two words apart")
    }

    @Test("A record is scrubbed in its message")
    func scrubsRecord() {
        let s = scrubber([.calendar("Therapy")])
        let record = PCErrorRecord(
            subject: .calendar(id: 3),
            operation: "calendarList.archive",
            message: "Couldn't archive Therapy",
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let out = s.scrub(record)

        #expect(!out.message.contains("Therapy"))
        #expect(out.operation == "calendarList.archive")
        // Ids are kept: they correlate rows and identify nothing about the user.
        #expect(out.subject == .calendar(id: 3))
        #expect(out.timestamp == record.timestamp)
    }
}
