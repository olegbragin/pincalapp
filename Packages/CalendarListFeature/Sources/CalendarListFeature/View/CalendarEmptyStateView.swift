//
//  CalendarEmptyStateView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct CalendarEmptyStateView: View {
    var isArchived: Bool = false

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isArchived ? "archivebox" : "calendar")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text(isArchived ? .noArchivedCalendars : .noCalendarsPressToAdd)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        // Named, and named *differently* for archived versus active.
        //
        // "The calendar list is empty" and "the archived list is empty" are different facts
        // and a test that cannot tell them apart will report the wrong one. More usefully,
        // this is the only reliable way to ask whether seed data arrived: a UI test that
        // assumed seeding and found no day cells had no way to distinguish "not seeded"
        // from "seeded but not rendered", and those need opposite fixes.
        .accessibilityIdentifier(isArchived ? "calendar-list-empty-archived" : "calendar-list-empty-active")
    }
}

#Preview {
    CalendarEmptyStateView()
}
