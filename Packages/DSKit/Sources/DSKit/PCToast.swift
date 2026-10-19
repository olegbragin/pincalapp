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

    var alignment: Alignment {
        self == .top ? .top : .bottom
    }

    var edge: Edge {
        self == .top ? .top : .bottom
    }
}

/// Presents one toast, driven by an `isPresented` binding, through a `PCToastStack`.
///
/// **The binding stays the owner of whether a toast is showing.** This never *decides* to
/// dismiss a toast; it only reports a dismissal back. A failed save is the only notice that
/// the user's work is not on disk, and a presenter that could retire it on its own would make
/// that depend on a timer rather than on the thing that knows. So the flow is one way:
/// `isPresented` goes true, a toast is added to the stack; it goes false, the stack is
/// emptied. Whatever set the flag has already done the work.
///
/// **The stack is supplied, not created here.** A presenter that owned its own stack would
/// still allow only one toast per `.pcToast`, which is the thing a stack exists to fix — three
/// modifiers each with a private stack overlay one another rather than stacking. So the screen
/// makes one `@State` stack and hands it to every toast it raises, and they queue.
public struct PCToastPresenter: ViewModifier {
    @Binding private var isPresented: Bool
    private let stack: PCToastStack
    private let position: PCToastPosition
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let backgroundColor: Color
    private let progress: Double?
    private let progressActiveColor: Color
    private let progressRemainingColor: Color
    private let identifier: String
    private let actionIdentifier: String

    /// Which toast in the shared stack this presenter put there, so a tick can find it again.
    @State private var toastID: UUID?

    public init(
        isPresented: Binding<Bool>,
        stack: PCToastStack,
        position: PCToastPosition = .bottom,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        backgroundColor: Color,
        progress: Double? = nil,
        progressActiveColor: Color = .white,
        progressRemainingColor: Color = .white.opacity(0.3),
        identifier: String = "pc-toast",
        actionIdentifier: String = "pc-toast-action"
    ) {
        self._isPresented = isPresented
        self.stack = stack
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
            .pcToastStack(
                stack,
                position: position,
                backgroundColor: backgroundColor,
                progressActiveColor: progressActiveColor,
                progressRemainingColor: progressRemainingColor,
                // Put the flag back when the user takes the toast, so the next occurrence of
                // the same condition can raise another one. `onChange` compares the old and
                // new value and does nothing when they match, so a flag left standing at
                // `true` would silently swallow every later failure of the same kind.
                onDismiss: { isPresented = false }
            )
            // `id`, not `onChange`: `onChange` does not fire for a toast that is *already*
            // presented on the first render, so a screen that restored straight into an error
            // would come up with its error toast missing. `task(id:)` runs on appear as well as
            // on every change, which is what "bind this to the stack" needs.
            .task(id: isPresented) {
                guard isPresented else {
                    // Only this presenter's own toast. The stack is shared, so a
                    // `dismissAll()` here would take the other presenters' toasts down with
                    // it — clearing the Retry because an archive window happened to close.
                    if let toastID {
                        stack.dismiss(toastID)
                    }
                    toastID = nil
                    return
                }
                let toast = PCToast(
                    message: message,
                    actionTitle: actionTitle,
                    action: action,
                    identifier: identifier,
                    actionIdentifier: actionIdentifier,
                    progress: progress
                )
                stack.present(toast)
                toastID = toast.id
            }
            // The window belongs to the feature, which counts it down and decides when the
            // binding goes false. This only mirrors that count into the stack so the bar moves.
            .onChange(of: progress) { _, newValue in
                guard let toastID else { return }
                stack.update(toastID, progress: newValue)
            }
    }
}

public extension View {
    /// Presents a toast at the given position, bound to `isPresented`.
    ///
    /// `progress` is optional and `nil` means **no bar at all** — pass one only for a toast
    /// that really does expire, because a bar is a promise that something is about to end.
    func pcToast(
        isPresented: Binding<Bool>,
        stack: PCToastStack,
        position: PCToastPosition = .bottom,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        backgroundColor: Color,
        progress: Double? = nil,
        progressActiveColor: Color = .white,
        progressRemainingColor: Color = .white.opacity(0.3),
        identifier: String = "pc-toast",
        actionIdentifier: String = "pc-toast-action"
    ) -> some View {
        modifier(
            PCToastPresenter(
                isPresented: isPresented,
                stack: stack,
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
