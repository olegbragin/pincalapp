//
//  ObjectBoxFactory.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation
import ObjectBox

public enum ObjectBoxFactory {
    private static let databaseName = "p_calendars"

    /// Creates the persistent store the app runs on.
    ///
    /// `directory` defaults to the fixed application-support location, so the production call site
    /// is unchanged. It is a parameter because that location used to be the *only* one reachable,
    /// which made this function untestable: exercising it meant writing to the user's real
    /// database, so every test used `makeInMemoryStore(named:)` instead and the production path
    /// ended up with no coverage at all. The shared path was therefore invisible — it looked
    /// fine, because nothing ran it twice.
    ///
    /// Naming the directory also makes independent stores safe by construction rather than by
    /// convention. `makeInMemoryStore(named:)` depends on every caller remembering to pass a
    /// unique name; this does not.
    public static func makePersistentStore(directory: URL? = nil) -> Store {
        let url = directory ?? defaultDirectory()
        try! FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return try! Store(directoryPath: url.path)
    }

    /// In-memory store for tests/previews — uses ObjectBox `memory:` prefix (no disk I/O)
    public static func makeInMemoryStore(named: String) throws -> Store {
        try Store(directoryPath: "memory:\(named)")
    }

    /// The fixed production location: `applicationSupport/<bundleId>/p_calendars`.
    ///
    /// Split out from `makePersistentStore` so the path can be asserted on without opening a
    /// store, which is what lets a test check the production wiring without writing to it.
    ///
    /// `bundleIdentifier` is a parameter for the same reason: the real value comes from the host
    /// app, and a test running inside a bundle-less xctest process would otherwise resolve to the
    /// fallback and be comparing against the wrong path.
    public static func defaultDirectory(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.crucialsoftware.PinCalApp"
    ) -> URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent(databaseName)
    }
}
