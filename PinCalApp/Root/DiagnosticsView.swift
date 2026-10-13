//
//  DiagnosticsView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import SwiftUI
import CorePersistence
import DSKit

/// Shows what the app has recorded going wrong, and shares it.
///
/// Reached only where `PCDiagnosticsGate` allows it, so this can assume it is being opened on
/// purpose.
///
/// The list shows **real** names, not the pseudonyms. The scrambler runs at export for the file,
/// which is what crosses the device boundary; on-screen text never leaves the handset, and a
/// report you are staring at is much harder to match against the app if every calendar is called
/// `<calendar-1>`.
struct DiagnosticsView: View {
    @Environment(\.pcErrorReporting) private var reporting
    @Environment(\.calendarCache) private var cache
    @Environment(\.pcVibe) private var vibe

    @State private var records: [PCErrorRecord] = []
    @State private var shareURL: URL?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            /// A filled `Rectangle` rather than a `.background` on the content, so the fill covers
            /// the screen no matter how little the content occupies.
            ///
            /// `.background` was applied to a `Group`, which is only as large as the union of its
            /// children's frames — and a `VStack` takes only the size it needs. So the empty state
            /// painted its cream behind itself and left the rest of the screen the system
            /// background, reading as a card floating on white rather than a themed screen.
            /// `.ignoresSafeArea()` because a fill that stops at the safe-area edge leaves a white
            /// strip under the status bar and the home indicator. Same construction as
            /// `RootDetailView`.
            Rectangle()
                .fill(vibe.color(for: .backgroundMain))
                .ignoresSafeArea()
            content
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: preparedURL ?? placeholderURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    // A `ShareLink` needs its item up front, and the file has to exist before the
                    // button is drawn. Until it does the button is disabled rather than absent, so
                    // the toolbar does not change shape once the archive is ready.
                    .disabled(preparedURL == nil)
                    .accessibilityIdentifier("diagnostics-share-button")
                }
            }
        }
        .task {
            records = await reporting.records()
            preparedURL = await makeArchive()
            isLoading = false
        }
    }

    // MARK: - Content

    /// Which of the three states the screen is in.
    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
        } else if records.isEmpty {
            emptyState
        } else {
            list
        }
    }

    /// `.scrollContentBackground(.hidden)` so the `Rectangle` behind it actually shows.
    ///
    /// A `List` paints its own system background material, which would otherwise cover the themed
    /// fill entirely — so without this the list renders correctly in isolation and wrong in place.
    /// The loading and empty branches draw no `List`, so this is the only place it is needed. Same
    /// pairing as `AddEditEventListView`.
    private var list: some View {
        List {
            Section {
                ForEach(records, id: \.timestamp) { record in
                    row(for: record)
                }
            } header: {
                Text("\(records.count) recorded")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(for record: PCErrorRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.operation)
                .font(.headline)
                .accessibilityIdentifier("diagnostics-operation")
            Text(record.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("\(record.timestamp.formatted(date: .abbreviated, time: .standard)) · \(describe(record.subject))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func describe(_ subject: PCErrorSubject) -> String {
        switch subject {
        case let .calendar(id): "calendar #\(id)"
        case let .batch(id): "batch #\(id)"
        case .storage: "storage"
        case .unknown: "unknown"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing recorded")
                .font(.headline)
            Text("Failures will appear here as they happen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("diagnostics-empty")
    }

    // MARK: - Archive

    /// The file to share, built once when the screen opens.
    ///
    /// Built eagerly rather than at the moment Share is tapped: `ShareLink` takes its item by
    /// value, so it cannot produce one on demand, and the alternative — a share sheet presented by
    /// hand — is a larger surface than a report screen warrants.
    @State private var preparedURL: URL?

    /// Lets `ShareLink` hold a valid item while `preparedURL` is still `nil`, which the disabled
    /// state above covers. Never presented: the button cannot be tapped in that state.
    private var placeholderURL: URL {
        URL(fileURLWithPath: "/dev/null")
    }

    private func makeArchive() async -> URL? {
        let scrubber = await makeScrambler()
        let payload = PCDiagnosticsArchive.makePayload(records: records, scrubber: scrubber)
        return PCDiagnosticsArchive.write(payload)
    }

    /// Collects every name that has to be redacted, from the calendars themselves.
    ///
    /// Read from storage rather than from the table because the table stores ids, not names. And
    /// read *at export* so a name added after a failure was recorded is still scrubbed if it turns
    /// up in that failure's message.
    ///
    /// A read failure here yields an empty map: better a report that redacts less than it should
    /// than no report at all. Which is a real limitation — the names it missed are exactly the ones
    /// a failing database was least able to hand over.
    private func makeScrambler() async -> PCDiagnosticsScrambler {
        // The cache is optional in the environment because the environment key is, and a view
        // rendered outside the app root gets nil. Treated the same as a read failure below.
        guard let cache, let calendars = try? await cache.getAllCalendars() else {
            return PCDiagnosticsScrambler(names: [])
        }
        var names: [PCDiagnosticsName] = []
        for calendar in calendars {
            names.append(.calendar(calendar.name))
            for batch in calendar.eventBatches {
                names.append(.batch(batch.name))
                for event in batch.events {
                    names.append(.event(event.name))
                }
            }
        }
        return PCDiagnosticsScrambler(names: names)
    }
}
