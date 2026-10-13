//
//  PCErrorRecorder.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import CorePersistence

/// Turns anything that was thrown into a `PCErrorRecord` and hands it to the reporter.
///
/// Exists as a separate type from `ObjectBoxPCErrorReporter` because of who can see what. Only the
/// app target imports `CorePersistence`, so this is the *only* place that can hold the reporter and
/// also know about the feature packages' failure types — which is the same reason
/// `PPErrorConformance.swift` sits here.
///
/// Also the only place that can cope with the errors that are **not** `PCError`. Most of what this
/// app throws is a raw ObjectBox error that has never been through a package's vocabulary, and
/// those are the majority of real failures. They are wrapped rather than dropped, under
/// `.storage` and the operation the caller was attempting, because a table that recorded only the
/// errors we happened to give a type to would miss most of what actually went wrong.
///
/// `nonisolated` throughout: this type is declared in a target whose
/// `SWIFT_DEFAULT_ACTOR_ISOLATION` is `MainActor`, so without it every member would be
/// main-actor-isolated — which would put a diagnostics write on the main actor's critical path and
/// make the recorder untestable without hopping to it. Recording holds nothing but a `Sendable`
/// port and hands off to a `Task`, so there is no isolation to claim in the first place.
nonisolated struct PCErrorRecorder: Sendable {
    private let reporter: any PCErrorReporting

    nonisolated init(reporter: any PCErrorReporting) {
        self.reporter = reporter
    }

    /// Records a thrown error against the operation that was being attempted.
    ///
    /// Fire-and-forget: every caller is a synchronous view callback, and making the UI await a
    /// diagnostics write would put the reporter on the path of a user's tap. Recording is best
    /// effort by construction and cannot fail, so there is nothing to await *for* — but the `Task`
    /// is still spawned rather than detached, because a detached task has no ordering relative to
    /// the app's own work and a record written after the app has moved on is less useful than one
    /// written in order.
    nonisolated func record(_ error: any Error, operation: String) {
        let record: PCErrorRecord
        if let conformed = error as? any PCError {
            record = conformed.pcRecord()
        } else {
            record = PCErrorRecord(
                subject: .storage,
                operation: operation,
                message: error.pcFallbackMessage
            )
        }
        let reporter = self.reporter
        Task { await reporter.record(record) }
    }
}
