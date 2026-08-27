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
    private let inactiveContent: () -> AnyView

    public init(
        isEditing: Binding<Bool>,
        action: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder activeContent: @escaping () -> AnyView = {
            AnyView(Image(systemName: "checkmark"))
        },
        @ViewBuilder inactiveContent: @escaping () -> AnyView = {
            AnyView(Text("Edit"))
        }
    ) {
        self._isEditing = isEditing
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
            } else {
                inactiveContent()
            }
        }
    }
}

#Preview {
    PCEditButton(isEditing: .constant(true))
    PCEditButton(isEditing: .constant(false))
}