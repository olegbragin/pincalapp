//
//  ObjectBoxPCErrorReporter.swift
//  CorePersistence
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation

@preconcurrency import ObjectBox

/// Where failures are recorded.
///
/// A protocol rather than the concrete type so that a caller in the app target — which cannot see
/// a feature package's internals but can see this — can be handed something it does not have to
/// know is ObjectBox underneath. The mirror of `CalendarRepository`, and for the same reason.
public protocol PCErrorReporting: Sendable {
    /// Records a failure. Never throws and never traps; see the implementation.
    func record(_ error: any PCError) async
    /// Records an already-reduced failure.
    func record(_ record: PCErrorRecord) async
    /// Every stored failure, newest last.
    func records() async -> [PCErrorRecord]
    func clear() async
}

/// A reporter that keeps nothing.
///
/// The default for any environment that has not been given a real one — previews, and tests that
/// render a view without standing up a database. Silently dropping is the right behaviour for a
/// place that has nowhere to write, and the alternative — trapping, or requiring every preview to
/// build a store — would make the common case harder than the real one.
public struct NoopPCErrorReporter: PCErrorReporting {
    public init() {}

    public func record(_ error: any PCError) async {}
    public func record(_ record: PCErrorRecord) async {}
    public func records() async -> [PCErrorRecord] {
        []
    }

    public func clear() async {}
}

/// Records failures in the same ObjectBox store the calendars live in — a separate box, never the
/// same one, and never `saveCalendar`.
///
/// `saveCalendar` is read-modify-write with a destructive step in the middle: it deletes every
/// batch absent from the incoming set. Routing diagnostics through it would mean a failure report
/// could delete a user's events, which is the exact opposite of what a failure report is for.
///
/// An actor because recording happens from whichever screen happened to fail, and because the
/// eviction below is a read followed by a write: two concurrent recordings could otherwise both
/// read a full table and both believe they were the one that had to clear it.
public actor ObjectBoxPCErrorReporter: PCErrorReporting {
    /// How many failures are kept.
    ///
    /// Bounded because the table is written by *the app failing*, and an app that fails in a loop
    /// — which is precisely when someone is going to open this screen — would otherwise grow the
    /// file until the device is out of room. The newest survive; the oldest go, because the
    /// failure being investigated is nearly always the recent one and the crash-loop noise that
    /// precedes it is the least interesting part.
    public static let capacity = 200

    private nonisolated(unsafe) let entryBox: Box<PPErrorEntry>

    public init(store: Store) {
        entryBox = store.box(for: PPErrorEntry.self)
    }

    public func record(_ error: any PCError) async {
        insert(error.pcRecord())
    }

    public func record(_ record: PCErrorRecord) async {
        insert(record)
    }

    /// The actual write. Non-async so the two `record` entry points above share it without one
    /// having to `await` the other — they are the same operation reached two ways, and an
    /// overload pair that calls itself is easy to misread as two behaviours.
    private func insert(_ record: PCErrorRecord) {
        // Nothing here throws, and that is the whole design.
        //
        // This is reached *because* something already went wrong. If recording could also fail —
        // disk full, a closed store, a migration mid-flight — it would be converting one fault
        // into a second, and the second is the one with no error path left to report it on. So
        // every step is best-effort and the failure to record is dropped rather than escalated.
        //
        // The consequence worth stating: a silent gap in the table means recording broke, not that
        // nothing happened. That is the better of the two failure modes, but it is a gap.
        //
        // "Never throws" is not merely this `catch` — `record` has no `throws` in its signature,
        // so a caller cannot be made to handle a recording failure even if one were added below.
        // The `catch` is what keeps that promise true rather than a promise the signature makes.
        do {
            try entryBox.put(PPErrorEntry(record: record))
            try evictOverflow()
        } catch {
            // Deliberately swallowed. See above.
        }
    }

    public func records() async -> [PCErrorRecord] {
        (try? entryBox.all())?
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.asRecord() } ?? []
    }

    /// Discards every stored failure.
    ///
    /// Swallows the error for the same reason `record` does — a diagnostics table that cannot
    /// clear itself is not worth failing the caller over — but assigns the result to `_` rather
    /// than leaving it bare. `try?` on its own statement discards a non-`Void` result, which
    /// `removeAll()` is not, and that reads as a mistake to anyone auditing the file.
    public func clear() async {
        _ = try? entryBox.removeAll()
    }

    /// Drops everything past `capacity`, oldest first.
    ///
    /// By timestamp rather than by id: ids are assigned in write order, which is close enough, but
    /// a clock adjustment — an NTP correction while the device is offline — can put a row written
    /// earlier behind one written later. The table is read by a person deciding what to look at,
    /// so ordering by when it happened is the property worth being correct about.
    private func evictOverflow() throws {
        let all = try entryBox.all()
        guard all.count > Self.capacity else { return }
        let overflow = all.count - Self.capacity
        let oldest = all
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(overflow)
            .map(\.id)
        try entryBox.remove(oldest)
    }
}
