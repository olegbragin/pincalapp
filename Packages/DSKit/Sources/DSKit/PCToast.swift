//
//  PCToast.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import SwiftUI

/// Where the toast presents itself relative to the modified content.
public enum PCToastPosition {
    case top
    case bottom

    var alignment: Alignment { self == .top ? .top : .bottom }
    var edge: Edge { self == .top ? .top : .bottom }
}

/// A reusable toast. It owns its placement (top/bottom) and renders a message,
/// an optional action label and a linear progress bar. Presentation is driven by
/// the `isPresented` binding; the progress value is supplied by the caller (e.g.
/// from a `PCTimeoutProgress`). Pure SwiftUI, so it is platform-agnostic.
public struct PCToast: ViewModifier {
    @Binding private var isPresented: Bool
    private let position: PCToastPosition
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let backgroundColor: Color
    private let progress: Double
    private let progressActiveColor: Color
    private let progressRemainingColor: Color
    private let identifier: String
    private let actionIdentifier: String

    public init(
        isPresented: Binding<Bool>,
        position: PCToastPosition = .bottom,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        backgroundColor: Color,
        progress: Double,
        progressActiveColor: Color = .white,
        progressRemainingColor: Color = .white.opacity(0.3),
        identifier: String = "pc-toast",
        actionIdentifier: String = "pc-toast-action"
    ) {
        self._isPresented = isPresented
        self.position = position
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.backgroundColor = backgroundColor
        self.progress = progress
        self.progressActiveColor = progressActiveColor
        self.progressRemainingColor = progressRemainingColor
        self.identifier = identifier
        self.actionIdentifier = actionIdentifier
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: position.alignment) {
                if isPresented {
                    toastView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .transition(.move(edge: position.edge).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }

    private var toastView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle {
                    // A `Button`, not just a `Text` inside a tap-gesture.
                    //
                    // The whole toast was tappable, which meant the only way for a UI test
                    // to reach the action was to tap the toast *body* — so "press Undo" was
                    // not expressible, only "tap the toast somewhere near the right". A
                    // button gives the action its own element, and with it an identifier.
                    Button {
                        action?()
                        isPresented = false
                    } label: {
                        Text(actionTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .accessibilityIdentifier(actionIdentifier)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            PCLinearProgressBar(
                progress: progress,
                activeColor: progressActiveColor,
                remainingColor: progressRemainingColor,
                height: 4
            )
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .contentShape(Rectangle())
        // Named so a test can ask whether a toast is on screen at all, instead of matching
        // on the message text. Toasts are transient, so that question needs an answer that
        // is not "read some label and hope".
        //
        // `.contain` is what makes the Undo button reachable as its own element: without it
        // SwiftUI merges the toast's children and the button's identifier matches nothing.
        // Safe here and **not** safe on a list card — applied to a card this modifier
        // rewrites the subtree and the card's name stops being exposed as a `StaticText`,
        // which broke 30 tests when it was tried there. A toast is a leaf overlay with two
        // children; a card is a container full of things other code reads by name.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .onTapGesture {
            action?()
            isPresented = false
        }
    }
}

public extension View {
    /// Presents a toast at the given position, bound to `isPresented`.
    func pcToast(
        isPresented: Binding<Bool>,
        position: PCToastPosition = .bottom,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        backgroundColor: Color,
        progress: Double,
        progressActiveColor: Color = .white,
        progressRemainingColor: Color = .white.opacity(0.3),
        identifier: String = "pc-toast",
        actionIdentifier: String = "pc-toast-action"
    ) -> some View {
        modifier(
            PCToast(
                isPresented: isPresented,
                position: position,
                message: message,
                actionTitle: actionTitle,
                action: action,
                backgroundColor: backgroundColor,
                progress: progress,
                progressActiveColor: progressActiveColor,
                progressRemainingColor: progressRemainingColor,
                identifier: identifier,
                actionIdentifier: actionIdentifier
            )
        )
    }
}
