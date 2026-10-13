//
//  PCDiagnosticsScrambler.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import CorePersistence

/// A user-authored name that must not leave the device in an exported report.
///
/// Typed, not a bare `String`, so the pseudonyms it produces still say *what* was redacted. A
/// report where every name reads `<redacted-1>` cannot distinguish a batch that appeared in ten
/// failures from a calendar that appeared in one, and that distinction is most of what a report is
/// for.
nonisolated enum PCDiagnosticsName: Hashable, Sendable {
    case calendar(String)
    case batch(String)
    case event(String)

    nonisolated var value: String {
        switch self {
        case let .calendar(name), let .batch(name), let .event(name): name
        }
    }

    /// `fileprivate` rather than `private`: the scrambler below reads it to build a token, and
    /// `private` at member scope stops at the enclosing type.
    fileprivate nonisolated var label: String {
        switch self {
        case .calendar: "calendar"
        case .batch: "batch"
        case .event: "event"
        }
    }

    /// Tie-break order for two entries sharing the same value. See the sort in the initializer.
    fileprivate nonisolated var rank: Int {
        switch self {
        case .calendar: 0
        case .batch: 1
        case .event: 2
        }
    }
}

/// Replaces user-authored names with stable pseudonyms, across arbitrary text.
///
/// Applied at **export**, not at record time, which is the whole reason it can work on unstructured
/// text: the stored rows keep real names so the table is still useful on the device, and the
/// redaction happens once, on the way out, to everything that is about to be shared.
///
/// Stable means the same name maps to the same pseudonym for the whole export. Without that a
/// calendar cannot be correlated across the rows that mention it, and the report degrades into a
/// list of unrelated incidents.
/// `nonisolated` throughout: this target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
/// redacting text is pure computation with no reason to need the main actor.
nonisolated struct PCDiagnosticsScrambler: Sendable {
    /// Longest first, which is what makes replacement correct rather than merely working.
    ///
    /// Names are replaced by scanning the text for each one in turn, so a short name that is a
    /// prefix of a longer one would otherwise consume the prefix and leave a remainder — "Work"
    /// matching inside "Workout" would yield `<redacted-1>out", which is both a leak (it reveals
    /// the length and tail of the real name) and a mangled report. Ordering by descending length
    /// means the longer name is always consumed first.
    private let ordered: [(name: String, token: String)]

    nonisolated init(names: [PCDiagnosticsName]) {
        // Longest first; ties broken all the way down, so the numbering does not depend on the
        // order the caller happened to walk the database in.
        //
        // The final tie-break on *kind* is load-bearing, not tidiness. Two entries can share a
        // value — a calendar and a batch both called "Work" — and then the first two comparators
        // call them equal, so `sorted` is free to return either. Whichever came out first would
        // win the token, and `Set` iteration order is not stable, so the same data could produce
        // `<calendar-1>` on one export and `<batch-1>` on the next. That is not a cosmetic
        // difference: two reports of the same session would no longer be comparable.
        let unique = Array(Set(names)).sorted(by: { (a: PCDiagnosticsName, b: PCDiagnosticsName) -> Bool in
            if a.value.count != b.value.count {
                return a.value.count > b.value.count
            }
            if a.value != b.value {
                return a.value < b.value
            }
            return a.rank < b.rank
        })

        var counters: [String: Int] = [:]
        var ordered: [(String, String)] = []
        var seen = Set<String>()

        for entry in unique {
            // Blank names are what an emptied field and a default template produce, and scrubbing
            // one would replace every space in every message — turning a whole report into
            // pseudonyms and destroying the text it was meant to preserve.
            guard !entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // One pseudonym per *value*, even when two kinds share it: the same text is the same
            // text, and a report that read `calendar-1` in one place and `batch-2` in another for
            // one name would imply two things where there was one.
            guard seen.insert(entry.value).inserted else { continue }
            let label = entry.label
            let next = (counters[label] ?? 0) + 1
            counters[label] = next
            ordered.append((entry.value, "<\(label)-\(next)>"))
        }

        self.ordered = ordered
    }

    /// Replaces every known name in `text`.
    nonisolated func scrub(_ text: String) -> String {
        var result = text
        for (name, token) in ordered {
            result = result.replacingOccurrences(of: name, with: token)
        }
        return result
    }

    /// Replaces every known name in a whole record.
    ///
    /// `message` is the field that needs it. `subject` and `operation` carry ids and fixed labels
    /// rather than user text — which is enforced at record time by `operationName` in
    /// `PPErrorConformance` — so they are left alone deliberately rather than incidentally.
    nonisolated func scrub(_ record: PCErrorRecord) -> PCErrorRecord {
        PCErrorRecord(
            subject: record.subject,
            operation: scrub(record.operation),
            message: scrub(record.message),
            timestamp: record.timestamp
        )
    }

    /// The names being redacted, for the archive to report how much was hidden.
    var redactionCount: Int {
        ordered.count
    }
}
