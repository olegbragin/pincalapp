//
//  CalendarRepositoryFactory.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import Foundation
import ObjectBox

public enum CalendarRepositoryFactory {
    /// The two things that share one database, returned together.
    ///
    /// A struct rather than two factories because they cannot be built independently: ObjectBox
    /// allows one `Store` per directory, so a caller wanting both would otherwise either open the
    /// database twice or have to know that they must. Returning them together is what makes
    /// "one store" a property of the wiring rather than something to remember.
    public struct Stack {
        public let repository: any CalendarRepository
        public let reporter: any PCErrorReporting

        public init(repository: any CalendarRepository, reporter: any PCErrorReporting) {
            self.repository = repository
            self.reporter = reporter
        }
    }

    /// Returns the storage stack for the current run: a seeded store when
    /// running under UI tests, otherwise the persistent production store. Keeps
    /// the test-vs-production branching out of `PinCalAppApp`.
    ///
    /// `directory` is forwarded to `ObjectBoxFactory.makePersistentStore(directory:)` and ignored on
    /// the seeded branch, which already gets a fresh temporary directory of its own. It exists so a
    /// test can build exactly what the app builds — same repository, same storage — pointed
    /// somewhere disposable. Passing it alongside `-UITestSeedData` is a mistake rather than an
    /// error: the seeded branch wins and the argument is silently unused.
    ///
    /// Throws. It did not, and that meant the *only* place a storage failure could be reported to
    /// the user could not report one: this is the production wiring, and opening the database is
    /// the first thing it does. A failure here used to trap at launch (via `try!` further down)
    /// rather than surface as anything a person could read or recover from.
    public static func makeDefault(directory: URL? = nil) throws -> Stack {
        let store: Store
        if UITestStoreFactory.shouldSeedForUITests() {
            store = try UITestStoreFactory.makeSeededStore()
        } else {
            store = try ObjectBoxFactory.makePersistentStore(directory: directory)
        }
        return Stack(
            repository: ObjectBoxCalendarStorage(store: store),
            reporter: ObjectBoxPCErrorReporter(store: store)
        )
    }
}
