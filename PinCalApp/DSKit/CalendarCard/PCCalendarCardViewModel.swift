//
//  PCCalendarCardViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

@Observable
final class PCCalendarCardViewModel {
    var name: String
    let numberOfColumns: Int
    let id: Int64
    let gradient: LinearGradient

    private(set) var isEditing: Bool = false
    var editingName: String = ""

    var onEditStarted: ((PCCalendarCardViewModel) -> Void)?
    var onEditCommitted: ((Int64, String) -> Void)?
    var onEditCancelled: (() -> Void)?

    init(calendar: any PCCalendarCardData) {
        self.id = calendar.id
        self.name = calendar.name
        self.numberOfColumns = calendar.numberOfColumns
        self.gradient = Self.makeGradient(for: calendar.id)
    }

    func startEditing() {
        guard !isEditing else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
        editingName = name
        onEditStarted?(self)
    }

    func confirmEdit() {
        guard isEditing else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty, newName != name {
            name = newName
            onEditCommitted?(id, newName)
        }
    }

    func cancelEdit() {
        guard isEditing else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        editingName = name
        onEditCancelled?()
    }

    private static func makeGradient(for id: Int64) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.82, green: 0.83, blue: 0.86),
                Color(red: 0.58, green: 0.60, blue: 0.63),
                Color(red: 0.42, green: 0.44, blue: 0.47)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
