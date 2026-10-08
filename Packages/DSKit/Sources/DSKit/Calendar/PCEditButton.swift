//
//  PCEditButton.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 26.03.2026.
//

import Foundation
import SwiftUI

public struct PCEditButton: View {
    @Binding var isEditing: Bool
    private let action: (Bool) -> Void
    private let activeContent: () -> AnyView
    private let inactiveContent: (() -> AnyView)?

    /// The label shown while not editing.
    ///
    /// Required rather than defaulted: `DSKit` does not localize, so there is no sensible default
    /// to fall back on — a default here would be a word chosen by this package, which is the one
    /// thing it must not do. `nil` for `inactiveContent` means "use this".
    ///
    /// The name rather than a bare `label` because callers pass it positionally after `isEditing`,
    /// and `title` would read as a navigation title at a glance.
    public let editTitle: String

    public init(
        isEditing: Binding<Bool>,
        editTitle: String,
        action: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder activeContent: @escaping () -> AnyView = {
            AnyView(Image(systemName: "checkmark"))
        },
        inactiveContent: (() -> AnyView)? = nil
    ) {
        self._isEditing = isEditing
        self.editTitle = editTitle
        self.action = action
        self.activeContent = activeContent
        self.inactiveContent = inactiveContent
    }

    public var body: some View {
        Button {
            action(isEditing)
        } label: {
            if isEditing {
                activeContent()
            } else if let inactiveContent {
                inactiveContent()
            } else {
                Text(editTitle)
            }
        }
    }
}

#Preview {
    PCEditButton(isEditing: .constant(true), editTitle: "Edit")
    PCEditButton(isEditing: .constant(false), editTitle: "Edit")
}
