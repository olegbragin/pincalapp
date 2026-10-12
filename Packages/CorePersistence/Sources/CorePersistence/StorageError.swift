//
//  StorageError.swift
//  CorePersistence
//
//  Created by Oleg Bragin on 11.10.2026.
//

import Foundation

/// Failures this package raises in its own words.
///
/// Every other error reaching callers from here is an ObjectBox error, thrown straight through
/// and meaning whatever ObjectBox meant. That is fine for a transport failure — the layer above
/// only needs to know a write did not land — and useless for one this package decides itself.
///
/// A missing batch is that second kind. ObjectBox's `get` returns `nil` for "no such row", which
/// is a legitimate answer, so the question of whether a batch referenced by id *should* exist is
/// this package's to answer rather than ObjectBox's. It is answered by throwing: the caller was
/// handed a set that omits an existing row, and writing that set would destroy data that was
/// never asked to be destroyed.
///
/// Raw cases, deliberately — what to *say* about any of this belongs to whoever presents it.
public enum StorageError: Error, Equatable {
    /// A batch referenced by a non-zero id was not in storage.
    ///
    /// Distinct from a failed *lookup*: `get` throwing is ObjectBox's error and propagates as
    /// itself. This is `get` succeeding and answering "no such row", which for a row the caller
    /// said exists is a contradiction rather than an absence.
    case batchMissing(id: Int64)

    /// A calendar referenced by id was not in storage. See `batchMissing` for why this throws.
    case calendarMissing(id: Int64)
}
