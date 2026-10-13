//
//  PPErrorConformance.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import CalendarListFeature
import CorePersistence
import SingleCalendarFeature

/// Conforms the feature packages' failures to `PCError`, from above every package.
///
/// This file exists instead of conformances written inside the packages that own the types
/// because those packages do not — and should not — depend on `CorePersistence`. `StorageError`
/// is the one failure that can conform where it is declared, and it does, in its own file.
///
/// Swift permits this: a module that can see both the type and the protocol may conform them. The
/// app target imports every package, so it can see all three and needs no new dependency edge to
/// do it. `@retroactive` is required and is the compiler saying so — both the type and the
/// protocol belong to other modules, which is the case it exists to flag. If a feature package
/// ever grows its own conformance, this one has to go, or the type gets a second conformance and
/// stops compiling.
///
/// Nothing here records anything. These conformances only make a failure *describable*; the
/// reporter and the call sites that reach for it are separate work, so this is inert on its own.
///
/// Every member below is `nonisolated` for a reason worth keeping: this target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the packages do not, so an unannotated
/// declaration here is MainActor-isolated while the types being conformed are not — and a
/// conformance that crosses into isolated code is a concurrency error, not a warning. These two
/// types are plain `Sendable` structs with immutable fields, so there is nothing to isolate and
/// `nonisolated` states what is already true rather than asserting something new.

extension PCCalendarListWriteFailure: @retroactive PCError {
    public nonisolated func pcRecord() -> PCErrorRecord {
        PCErrorRecord(
            subject: subjectCalendarID.map { PCErrorSubject.calendar(id: $0) } ?? .unknown,
            operation: "calendarList.\(operationName)",
            message: message
        )
    }

    /// The calendar this write was aimed at, or `nil` when there is not one yet.
    ///
    /// Only `create` has none — the row it would name does not exist, which is why its subject is
    /// `.unknown` rather than a made-up id that would sit in the table looking like a real one.
    private nonisolated var subjectCalendarID: Int64? {
        switch operation {
        case .create: nil
        case let .rename(id, _), let .archive(id), let .restore(id), let .permanentlyDelete(id): id
        }
    }

    /// The bare operation name, as a report groups it.
    ///
    /// The associated names are deliberately dropped. `create(name:)` and `rename(_, newName:)`
    /// carry user text, and this string is the field a report is most likely to be pasted,
    /// screenshotted or pasted into a chat — so it holds no more than the operation itself.
    private nonisolated var operationName: String {
        switch operation {
        case .create: "create"
        case .rename: "rename"
        case .archive: "archive"
        case .restore: "restore"
        case .permanentlyDelete: "permanentlyDelete"
        }
    }
}

extension PCFailedSave: @retroactive PCError {
    public nonisolated func pcRecord() -> PCErrorRecord {
        PCErrorRecord(
            subject: .calendar(id: calendarID),
            operation: "eventBatch.save",
            message: message
        )
    }
}
