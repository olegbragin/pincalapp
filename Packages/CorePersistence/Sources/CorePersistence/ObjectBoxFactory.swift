//
//  ObjectBoxFactory.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation
import ObjectBox

public struct ObjectBoxFactory {
    /// Creates a persistent store for production use
    public static func makePersistentStore() -> Store {
        let dbPath = try! getDatabasePath().path
        let store = try! Store(directoryPath: dbPath)
        return store
    }

    /// In-memory store for tests/previews — uses ObjectBox `memory:` prefix (no disk I/O)
    public static func makeInMemoryStore(named: String) throws -> Store {
        try Store(directoryPath: "memory:\(named)")
    }

    private static func getDatabasePath() throws -> URL {
        let databaseName = "p_calendars"
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier!)
        let directory = appSupport.appendingPathComponent(databaseName)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }
}
