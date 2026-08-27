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
            Text(isArchived
                ? "No archived calendars"
                : "Нет календарей. Нажмите «+», чтобы добавить.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    CalendarEmptyStateView()
}
