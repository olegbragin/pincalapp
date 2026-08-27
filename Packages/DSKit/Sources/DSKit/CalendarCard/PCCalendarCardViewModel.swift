//
//  PCCalendarCardViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

@Observable
public final class PCCalendarCardViewModel {
    public var name: String
    public var numberOfColumns: Int
    public let id: Int64
    public let isArchived: Bool
    public let gradient: LinearGradient

    public private(set) var isEditing: Bool = false
    public var editingName: String = ""

    public var onEditStarted: ((PCCalendarCardViewModel) -> Void)?
    public var onEditCommitted: ((Int64, String) -> Void)?
    public var onEditCancelled: (() -> Void)?
    public var onDelete: (() -> Void)?
    public var onRestore: (() -> Void)?
    public var onPermanentDelete: (() -> Void)?

    public init(id: Int64, name: String, numberOfColumns: Int, isArchived: Bool) {
        self.id = id
        self.name = name
        self.numberOfColumns = numberOfColumns
        self.isArchived = isArchived
        self.gradient = Self.makeGradient(for: id)
    }

    init(calendar: some PCCalendarCardData) {
        self.id = calendar.id
        self.name = calendar.name
        self.numberOfColumns = calendar.numberOfColumns
        self.isArchived = calendar.isArchived
        self.gradient = Self.makeGradient(for: calendar.id)
    }

    public func startEditing() {
        guard !isEditing, !isArchived else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
        editingName = name
        onEditStarted?(self)
    }

    public func confirmEdit() {
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

    public func cancelEdit() {
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