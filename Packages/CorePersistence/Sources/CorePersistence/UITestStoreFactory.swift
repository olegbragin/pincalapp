//
//  UITestStoreFactory.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 01.09.2026.
//

import Foundation
import ObjectBox

public struct UITestStoreFactory {
    public static let launchArgument = "-UITestSeedData"

    public static func makeSeededStore() -> Store {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pincal-uitest-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(
            at: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let store = try! Store(directoryPath: path.path)
        TestDataSeeder.seedUITestData(into: store)
        return store
    }

    public static func shouldSeedForUITests() -> Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}