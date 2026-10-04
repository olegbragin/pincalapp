//
//  ObjectBoxFactoryTests.swift
//  CorePersistenceTests
//
//  Created by Oleg Bragin on 04.10.2026.
//

import Foundation
import Testing
import ObjectBox
@testable import CorePersistence

/// Covers the store directory seam.
///
/// `makePersistentStore` had no parameters and resolved a fixed
/// `applicationSupport/<bundleId>/p_calendars`, so there was no way to reach it from a test
/// without writing to the user's real database. Every test used `makeInMemoryStore(named:)` instead
/// and the production path had no coverage at all — which is how a path shared by every caller went
/// unnoticed. These tests pin the seam down.
struct ObjectBoxFactoryTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pincal-store-factory-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("The store is opened at the requested directory, and the directory is created")
    func opensStoreAtRequestedDirectory() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ObjectBoxFactory.makePersistentStore(directory: directory)
        defer { store.close() }

        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    /// The property that actually matters for running tests at once: two callers naming two
    /// directories get two independent databases.
    ///
    /// With the old fixed path this was the hazard — every caller resolved to one physical file, so
    /// two processes opening it were two writers on one ObjectBox store. Asserting the paths
    /// differ would only prove the arguments differ; writing through one and reading from the
    /// other is what proves they are separate stores.
    @Test("Two stores at different directories do not see each other's writes")
    func storesAtDifferentDirectoriesAreIndependent() throws {
        let firstDirectory = temporaryDirectory()
        let secondDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }

        let first = ObjectBoxFactory.makePersistentStore(directory: firstDirectory)
        let second = ObjectBoxFactory.makePersistentStore(directory: secondDirectory)
        defer {
            first.close()
            second.close()
        }

        let calendar = PPCalendar(name: "Only In The First", year: 2026, numberOfColumns: 3)
        #expect(try first.box(for: PPCalendar.self).put(calendar) > 0)

        #expect(try second.box(for: PPCalendar.self).count() == 0)
        #expect(try first.box(for: PPCalendar.self).count() == 1)
    }

    /// The production location, stated rather than implied.
    ///
    /// This is the coupling the seam exists to route around, so it should be a visible fact rather
    /// than a path buried in a factory. `bundleIdentifier` is passed explicitly because an xctest
    /// process has no meaningful `Bundle.main.bundleIdentifier` and would otherwise resolve to the
    /// fallback — comparing against the wrong path and passing for the wrong reason.
    @Test("The default directory is application support, namespaced by bundle identifier")
    func defaultDirectoryIsNamespacedByBundleIdentifier() {
        let resolved = ObjectBoxFactory.defaultDirectory(bundleIdentifier: "com.example.PinCalApp")

        #expect(resolved.lastPathComponent == "p_calendars")
        #expect(resolved.deletingLastPathComponent().lastPathComponent == "com.example.PinCalApp")
        #expect(resolved.path.hasPrefix(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path))
    }

    /// Two bundle identifiers must not resolve to one store. This is the concrete harm of the
    /// default: shared by every caller of `makePersistentStore()`, and by the app and its tests
    /// alike.
    @Test("Different bundle identifiers resolve to different directories")
    func defaultDirectoryVariesByBundleIdentifier() {
        let first = ObjectBoxFactory.defaultDirectory(bundleIdentifier: "com.example.First")
        let second = ObjectBoxFactory.defaultDirectory(bundleIdentifier: "com.example.Second")

        #expect(first != second)
    }
}
