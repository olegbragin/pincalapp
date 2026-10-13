//
//  PCDiagnosticsArchive.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation
import UIKit
import CorePersistence

/// Builds the file that gets shared, and writes it somewhere shareable.
///
/// Two halves that must not be confused: the **payload** is what a person reads, and the **file**
/// is zlib-compressed so a long session's worth of failures is still a reasonable thing to attach
/// to a message. JSON alone is not compressed and never was — the compression is a separate step,
/// which is why the file is `.pcdiag` rather than `.json`.
nonisolated struct PCDiagnosticsArchive: Sendable {
    /// What is written. Plain structs rather than `PCErrorRecord` itself, so the on-disk shape is
    /// a deliberate format rather than whatever the domain type happens to be this month.
    struct Payload: Codable {
        let appVersion: String
        let osVersion: String
        let deviceModel: String
        let generatedAt: Date
        /// How many distinct names were redacted. Reported so the reader knows the report is
        /// scrubbed *and* whether anything was found to scrub — a zero here is worth knowing.
        let redactions: Int
        let records: [Record]
    }

    struct Record: Codable {
        let timestamp: Date
        let operation: String
        let subject: String
        let message: String
    }

    /// File extension for the compressed payload.
    static let fileExtension = "pcdiag"

    // MARK: - Building

    /// Builds the payload.
    ///
    /// `@MainActor` because `UIDevice` is main-actor-isolated, and the device and OS versions are
    /// exactly what a report needs to make sense — there is no non-UIKit way to ask. The caller is
    /// a SwiftUI view whose `.task` is already on the main actor, so this costs nothing.
    ///
    /// `write` below is *not* `@MainActor`: it only touches Foundation, and keeping it off the main
    /// actor means the file can be written from anywhere.
    @MainActor
    static func makePayload(records: [PCErrorRecord], scrubber: PCDiagnosticsScrambler) -> Payload {
        Payload(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            generatedAt: Date(),
            redactions: scrubber.redactionCount,
            records: records.map {
                let scrubbed = scrubber.scrub($0)
                return Record(
                    timestamp: scrubbed.timestamp,
                    operation: scrubbed.operation,
                    subject: describe(scrubbed.subject),
                    message: scrubbed.message
                )
            }
        )
    }

    /// A subject as text.
    ///
    /// Written out rather than encoded as an enum with an associated value, which `Codable` cannot
    /// synthesise for. Ids are kept: they are how two failures are correlated, and they identify
    /// nothing about the user.
    private static func describe(_ subject: PCErrorSubject) -> String {
        switch subject {
        case let .calendar(id): "calendar #\(id)"
        case let .batch(id): "batch #\(id)"
        case .storage: "storage"
        case .unknown: "unknown"
        }
    }

    // MARK: - Writing

    /// Writes the compressed payload and returns the file, or `nil` if it could not be written.
    ///
    /// Fails rather than throws: this is reached from a share button, and a share sheet with no
    /// file to share is not a better experience than one that explains itself. The caller shows
    /// nothing in that case, which is the honest outcome — the rows are still on screen.
    nonisolated static func write(_ payload: Payload) -> URL? {
        let encoder = JSONEncoder()
        // ISO 8601 rather than the default: a report is read by a person comparing timestamps
        // across devices, and `Codable`'s default double encoding is unreadable at a glance.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let json = try? encoder.encode(payload) else { return nil }
        // `compressed(using:)` throws rather than returning nil, which is a sharper contract than this
        // function's: a caller asking for an archive gets a file or nothing, never a half-written one.
        guard let compressed = try? (json as NSData).compressed(using: .zlib) as Data? else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "PinCal-diagnostics-\(formatter.string(from: Date())).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        do {
            try compressed.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
