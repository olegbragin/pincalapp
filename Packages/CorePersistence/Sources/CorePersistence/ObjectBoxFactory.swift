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
    ///
    /// **Throws**, where it used to `try!` on all three failure points.
    ///
    /// This is the only function that opens the user's real database, and with `try!` it had no
    /// way to report anything: a full disk, a locked container or a broken home directory ended
    /// the process at launch, with no message the user could read and no state to recover. The
    /// sibling `makeInMemoryStore` already threw, which is what makes this an oversight rather
    /// than a decision — the throwing path existed and was right there.
    ///
    /// `defaultDirectory()` throwing is the likeliest of the three to fire, because it is the
    /// one that *creates* the application-support directory.
    public static func makePersistentStore(directory: URL? = nil) throws -> Store {
        // `try` on the call rather than the whole expression: `directory` is already a `URL`, so
        // covering the `??` would imply the nil-coalescing itself can throw.
        let url = try directory ?? defaultDirectory()
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return try Store(directoryPath: url.path)
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
    ///
    /// Throws, and this is the call that most needs to: `create: true` means this *creates* the
    /// application-support directory, so it fails on a full or unavailable volume rather than
    /// merely resolving to something odd.
    public static func defaultDirectory(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.crucialsoftware.PinCalApp"
    ) throws -> URL {
        let appSupport = try FileManager.default.url(
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
