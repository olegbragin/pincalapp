//
//  PCToastStackModifier.swift
//  DSKit
//
//  Created by Oleg Bragin on 02.10.2026.
//

import SwiftUI

/// Draws a `PCToastStack` as vertically stacked toasts.
///
/// **Non-modal, deliberately.** No `.allowsHitTesting(false)` on the container, and no
/// dismiss-on-tap-outside. Both were considered and both are wrong here: a toast carrying a
/// Retry is the only route back to unsaved work, so it must not be dismissable by an
/// accidental touch somewhere else on the screen, and it must not swallow taps meant for the
/// content behind it. The stack overlays; it does not take over.
///
/// Tapping a toast *body* runs its action and removes it. Tapping elsewhere does nothing —
/// dismissal is the action button's business, not a side effect of touching the screen.
struct PCToastStackModifier: ViewModifier {
    let stack: PCToastStack
    let position: PCToastPosition
    let backgroundColor: Color
    let progressActiveColor: Color
    let progressRemainingColor: Color

    /// Called when a toast is dismissed by the user, after it leaves the stack.
    ///
    /// Separate from the removal because **removing a toast is not the same as saying it is no
    /// longer wanted.** A stack that is merely drained has lost nothing; a presenter bound to
    /// `isPresented` has to put that flag back to `false`, because a flag left `true` fires no
    /// `onChange` the next time the same condition comes round — so the *second* save failure
    /// would raise no toast at all.
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay(alignment: position.alignment) {
            if !stack.isEmpty {
                VStack(spacing: 8) {
                    // Reversed so the newest toast is drawn last — nearest the edge the user
                    // is looking at, and above the older ones where it can be reached.
                    ForEach(stack.toasts.reversed()) { toast in
                        PCToastView(
                            toast: toast,
                            backgroundColor: backgroundColor,
                            progressActiveColor: progressActiveColor,
                            progressRemainingColor: progressRemainingColor,
                            onDismiss: {
                                stack.dismiss(toast.id)
                                onDismiss?()
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .transition(.move(edge: position.edge).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stack.toasts.count)
    }
}

/// A single row. Separated from the stack so the one-toast presentation
/// (`PCToastPresenter`) is expressed in terms of it rather than duplicating its markup —
/// which is the whole reason this exists: the toast was drawn twice, once as a lone overlay
/// and once as a stack entry, and the two copies had already drifted.
struct PCToastView: View {
    let toast: PCToast
    let backgroundColor: Color
    let progressActiveColor: Color
    let progressRemainingColor: Color
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(toast.message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle = toast.actionTitle {
                    // A `Button`, not just a `Text` inside a tap-gesture.
                    //
                    // The whole toast was tappable, which meant the only way for a UI test
                    // to reach the action was to tap the toast *body* — so "press Undo" was
                    // not expressible, only "tap the toast somewhere near the right". A
                    // button gives the action its own element, and with it an identifier.
                    Button {
                        toast.action?()
                        onDismiss()
                    } label: {
                        Text(actionTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .accessibilityIdentifier(toast.actionIdentifier)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // A progress bar implies a countdown, so it is drawn only when there is one.
            // A toast that never expires must not imply that it will — which is why
            // `progress` is optional on the toast rather than a `0` that merely draws empty.
            if let progress = toast.progress {
                PCLinearProgressBar(
                    progress: progress,
                    activeColor: progressActiveColor,
                    remainingColor: progressRemainingColor,
                    height: 4
                )
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .contentShape(Rectangle())
        // Named so a test can ask whether a toast is on screen at all, instead of matching
        // on the message text. Toasts are transient, so that question needs an answer that
        // is not "read some label and hope".
        //
        // `.contain` is what makes the action button reachable as its own element: without it
        // SwiftUI merges the toast's children and the button's identifier matches nothing.
        // Safe here and **not** safe on a list card — applied to a card this rewrites the
        // subtree and the card's name stops being exposed as a `StaticText`, which broke 30
        // tests when it was tried there. A toast is a leaf overlay with two children; a card
        // is a container full of things other code reads by name.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(toast.identifier)
        .onTapGesture {
            toast.action?()
            onDismiss()
        }
    }
}

public extension View {
    /// Draws a toast stack over this view, newest at the bottom (or top).
    ///
    /// Attach this at the top of a screen — above any pushed content — so a toast raised by
    /// something underneath is still visible. A toast anchored to a screen that gets pushed
    /// over is invisible for exactly as long as it matters.
    func pcToastStack(
        _ stack: PCToastStack,
        position: PCToastPosition = .bottom,
        backgroundColor: Color = .black.opacity(0.85),
        progressActiveColor: Color = .white,
        progressRemainingColor: Color = .white.opacity(0.3),
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PCToastStackModifier(
                stack: stack,
                position: position,
                backgroundColor: backgroundColor,
                progressActiveColor: progressActiveColor,
                progressRemainingColor: progressRemainingColor,
                onDismiss: onDismiss
            )
        )
    }
}
