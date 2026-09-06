//
//  CalendarRepositoryFactory.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import Foundation
import ObjectBox

public enum CalendarRepositoryFactory {
    /// Returns the repository instance for the current run: a seeded store when
    /// running under UI tests, otherwise the persistent production store. Keeps
    /// the test-vs-production branching out of `PinCalAppApp`.
    public static func makeDefault() -> any CalendarRepository {
        if UITestStoreFactory.shouldSeedForUITests() {
            return ObjectBoxCalendarStorage(store: UITestStoreFactory.makeSeededStore())
        }
        return ObjectBoxCalendarStorage(store: ObjectBoxFactory.makePersistentStore())
    }
}
