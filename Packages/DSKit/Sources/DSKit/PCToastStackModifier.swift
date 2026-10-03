//
//  PCToastStackModifier.swift
//  DSKit
//
//  Created by Oleg Bragin on 02.10.2026.
//

import SwiftUI

/// Draws a `PCTostStack` as vertically stacked toasts.
///
/// **Non-modal, deliberately.** No `.allowsHitTesting(false)` on the container, and no
/// dismiss-on-tap-outside. Both were considered and both are wrong here: a toast carrying a
/// Retry is the only route back to unsaved work, so it must not be dismissable by an
/// accidental touch somewhere else on the screen, and it must not swallow taps meant for the
/// content behind it. The stack overlays; it does not take over.
///
/// Tapping a toast *body* runs its action and removes it, which is what the original single
/// toast did. Tapping elsewhere does nothing — dismissal is the action button's business,
/// not a side effect of touching the screen.
struct PCToastStackModifier: ViewModifier {

    let stack: PCTostStack
    let position: PCToastPosition
    let backgroundColor: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: position.alignment) {
            if !stack.isEmpty {
                VStack(spacing: 8) {
                    // Reversed so the newest toast is drawn last — nearest the edge the user
                    // is looking at, and above the older ones where it can be reached.
                    ForEach(stack.toasts.reversed()) { toast in
                        PCTostView(
                            toast: toast,
                            backgroundColor: backgroundColor,
                            onDismiss: { stack.dismiss(toast.id) }
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

/// A single row. Separated from the stack so the existing one-toast presentation can be
/// expressed in terms of it rather than duplicated.
struct PCTostView: View {

    let toast: PCTost
    let backgroundColor: Color
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
                    // A `Button`, not a `Text` inside a tap-gesture: the action needs its own
                    // element, and with it an identifier a test can press.
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

            if toast.duration != nil {
                // A progress bar implies a countdown, so it is only drawn when there is one.
                // A toast that never dismisses must not imply that it will.
                PCTostCountdownBar(duration: toast.duration ?? .seconds(5))
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .contentShape(Rectangle())
        // Named so a test can ask whether a toast is on screen at all, instead of matching on
        // the message text. Toasts are transient, so that question needs an answer that is
        // not "read some label and hope".
        //
        // `.contain` is what makes the action button reachable as its own element: without it
        // SwiftUI merges the toast's children and the button's identifier matches nothing.
        // Safe here and **not** safe on a list card — applied to a card this rewrites the
        // subtree and the card's name stops being exposed as a `StaticText`, which broke 30
        // tests when it was tried there. A toast is a leaf overlay with two children; a card is
        // a container full of things other code reads by name.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(toast.identifier)
        .onTapGesture {
            toast.action?()
            onDismiss()
        }
    }
}

/// A bar that empties over the toast's lifetime.
///
/// Decorative: it is not a `ProgressView` with a real bound, because the countdown is driven
/// by the stack's own scheduled removal and a second timer would be a second source of truth
/// for when the toast goes away.
private struct PCTostCountdownBar: View {

    let duration: Duration
    @State private var startedAt: Date?

    private var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var body: some View {
        GeometryReader { geometry in
            let total = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            let remaining = max(0, 1 - elapsed / max(total, 0.001))
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * remaining)
                }
        }
        .frame(height: 4)
        .onAppear { startedAt = Date() }
    }
}

public extension View {
    /// Draws a toast stack over this view, newest at the bottom (or top).
    ///
    /// Attach this at the top of a screen — above any pushed content — so a toast raised by
    /// something underneath is still visible. A toast anchored to a screen that gets pushed
    /// over is invisible for exactly as long as it matters.
    func pcToastStack(
        _ stack: PCTostStack,
        position: PCToastPosition = .bottom,
        backgroundColor: Color = .black.opacity(0.85)
    ) -> some View {
        modifier(
            PCToastStackModifier(
                stack: stack,
                position: position,
                backgroundColor: backgroundColor
            )
        )
    }
}