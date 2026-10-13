//
//  PPErrorEntry.swift
//  CorePersistence
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import ObjectBox

/// A stored `PCErrorRecord`.
///
/// Named `Entry` rather than `PCErrorRecord` on purpose: the Swift type is already
/// `PCErrorRecord`, and two types differing only by `PP`/`PC` is a distinction nobody reads
/// correctly under pressure. This one is private to storage; nothing outside the reporter should
/// need to name it.
///
/// The subject is flattened into a kind and an id rather than stored as the enum. ObjectBox has no
/// representation for a Swift enum with an associated value, and encoding it into one string would
/// make every read a parse. Two flat fields keep the query in the box.
class PPErrorEntry: Entity {
    var id: Id = 0
    var subjectKind: String = ""
    var subjectID: Int64 = 0
    var operation: String = ""
    var message: String = ""
    var timestamp: Date = .init()

    init() {}

    init(record: PCErrorRecord) {
        apply(record)
    }

    /// The row as a record. The inverse of `init(record:)`.
    func asRecord() -> PCErrorRecord {
        PCErrorRecord(
            subject: Self.subject(fromKind: subjectKind, id: subjectID),
            operation: operation,
            message: message,
            timestamp: timestamp
        )
    }

    /// Applies a record in place, so an updated row keeps its id.
    ///
    /// Not `put`-ing a fresh entity: that would give every update a new id, and the cap below
    /// evicts by oldest timestamp, so an updated row would move to the end of the table and an old
    /// failure could outlive the newest one simply by being touched.
    func apply(_ record: PCErrorRecord) {
        subjectKind = record.subject.kind
        subjectID = record.subject.id ?? 0
        operation = record.operation
        message = record.message
        timestamp = record.timestamp
    }

    private static func subject(fromKind kind: String, id: Int64) -> PCErrorSubject {
        switch kind {
        case "calendar": .calendar(id: id)
        case "batch": .batch(id: id)
        case "storage": .storage
        default: .unknown
        }
    }
}

extension PCErrorSubject {
    /// The stored spelling of this subject's kind. The id lives in its own column.
    var kind: String {
        switch self {
        case .calendar: "calendar"
        case .batch: "batch"
        case .storage: "storage"
        case .unknown: "unknown"
        }
    }

    /// The subject's id, or `nil` when it has none.
    ///
    /// Stored as `0` in the row for a subject with no id — see `PCErrorSubject.unknown` for why a
    /// made-up id would be worse than none.
    var id: Int64? {
        switch self {
        case let .calendar(id), let .batch(id): id
        case .storage, .unknown: nil
        }
    }
}
