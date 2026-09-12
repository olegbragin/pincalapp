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
    }

    init(calendar: some PCCalendarCardData) {
        self.id = calendar.id
        self.name = calendar.name
        self.numberOfColumns = calendar.numberOfColumns
        self.isArchived = calendar.isArchived
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
}