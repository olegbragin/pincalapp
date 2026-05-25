//
//  USEditButton.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 26.03.2026.
//

import Foundation
import SwiftUI

struct USEditButton: View {
    @Binding var isEditing: Bool
    private let action: (Bool) -> Void
    private let activeContent: () -> AnyView
    private let inactiveContent: () -> AnyView

    init(
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

    var body: some View {
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
    USEditButton(isEditing: .constant(true))
    USEditButton(isEditing: .constant(false))
}
