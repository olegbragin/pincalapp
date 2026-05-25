//
//  ObjectBoxFactory.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation
import ObjectBox

struct ObjectBoxFactory {
    static let shared = ObjectBoxFactory()
    private(set) var store: Store!

    private init() {
        // Инициализация Store, как показано выше
        store = try! Store(directoryPath: getDatabasePath().path)
    }

    private func getDatabasePath() -> URL {
        let databaseName = "p_calendars"
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier!
        )
        let directory = appSupport.appendingPathComponent(databaseName)
        try! FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }
}
