//
//  PCKeyboardAvoidable.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.08.2026.
//

import SwiftUI

private struct PCKeyboardInsetModifier: ViewModifier {
    @Environment(PCKeyboardState.self) private var keyboardState

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: keyboardState.keyboardHeight)
            }
            .animation(.easeInOut(duration: 0.25), value: keyboardState.keyboardHeight)
    }
}

private struct PCKeyboardScrollModifier<FocusedItem: Hashable>: ViewModifier {
    @Binding var focusedItem: FocusedItem?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .modifier(PCKeyboardInsetModifier())
                .onChange(of: focusedItem) { _, item in
                    guard let item else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(item, anchor: .bottom)
                    }
                }
        }
    }
}

extension View {

    /// Lifts the content above the keyboard while it is visible.
    ///
    /// Use for static layouts (forms, panels) without scrollable content.
    func keyboardAvoidable() -> some View {
        modifier(PCKeyboardInsetModifier())
    }

    /// Lifts the content above the keyboard and scrolls to the item identified
    /// by ``focusedItem`` whenever it becomes non-nil.
    ///
    /// Tag scrollable items with `.id(item)` matching the bound value.
    func keyboardAvoidable<FocusedItem: Hashable>(focusedItem: Binding<FocusedItem?>) -> some View {
        modifier(PCKeyboardScrollModifier(focusedItem: focusedItem))
    }
}
