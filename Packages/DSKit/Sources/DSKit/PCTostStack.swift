//
//  PCTostStack.swift
//  DSKit
//
//  Created by Oleg Bragin on 02.10.2026.
//

import Observation
import SwiftUI

/// One toast: a message, an optional action, and how long it lives.
///
/// A value, so a stack holds toasts and not references to mutable screens. The action is a
/// closure rather than a route because the two toasts that exist want different things —
/// Undo replays a delete, Retry replays a write — and neither is expressible as a destination.
public struct PCTost: Identifiable, Equatable {
    /// Identity. Stable for the toast's life, so stacking and removal animate correctly and a
    /// re-presented toast is not mistaken for the same one.
    public let id: UUID

    /// Whether this toast's action stays live. A Retry that has already been pressed, or an
    /// Undo whose window has closed, must not look actionable.
    public var actionTitle: String?

    /// Text on the action button. Kept optional because a plain notice needs no button.
    public var message: String

    /// Element identifier, so a UI test can ask "is a toast on screen" without matching text.
    public var identifier: String

    /// Element identifier for the action button, so a test presses the *action* rather than
    /// tapping the toast body and hoping it landed on the right third of it.
    public var actionIdentifier: String

    public var action: (() -> Void)?

    /// How long before it dismisses itself, or `nil` to stay until removed.
    ///
    /// A failed save passes `nil`: it must not fade unattended, because it is the only notice
    /// that the user's work is not on disk.
    public var duration: Duration?

    public init(
        id: UUID = UUID(),
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        identifier: String = "pc-toast",
        actionIdentifier: String = "pc-toast-action",
        duration: Duration? = .seconds(5)
    ) {
        self.id = id
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.identifier = identifier
        self.actionIdentifier = actionIdentifier
        self.duration = duration
    }

    public static func == (lhs: PCTost, rhs: PCTost) -> Bool {
        lhs.id == rhs.id
    }
}

/// Toasts waiting to be shown, newest last.
///
/// A stack rather than a single slot because two can be true at once: a save has failed *and*
/// a calendar was just archived. One slot would make the newer toast displace the older,
/// which loses the older one's action silently — and for Undo that means losing the ability to
/// undo something the user was never told they could.
///
/// **Not** the owner of whether a toast is shown. Each feature decides *when* to raise one;
/// this only holds them. That split is what lets the stack live at the top of the screen: the
/// feature publishes, and a presenter far above the navigation draws it.
@MainActor
@Observable
public final class PCTostStack {
    /// The pending toasts, oldest first — the order they are drawn in, so the newest is
    /// closest to the edge the user looks at last.
    public private(set) var toasts: [PCTost] = []

    /// The longest a stack is allowed to get. Toasts stack because two are occasionally
    /// true at once, not because a screen accumulates them; an unbounded stack would grow
    /// off-screen and cover the very content the messages are about.
    public var capacity = 3

    public init() {}

    /// Adds a toast and schedules its removal.
    ///
    /// Over-capacity drops the **oldest**, not the newest. A new message is the one the user
    /// just caused and is most likely to still care about; the oldest is the one whose window
    /// was about to close anyway.
    public func present(_ toast: PCTost) {
        toasts.append(toast)

        if toasts.count > capacity {
            toasts.removeFirst(toasts.count - capacity)
        }

        guard let duration = toast.duration else { return }
        let id = toast.id
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    /// Removes one toast. The action does not run: dismissal and activation are separate, so a
    /// toast that times out mid-countdown is gone without the user having pressed it.
    public func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    public func dismissAll() {
        toasts.removeAll()
    }

    /// Whether any toast is showing, for a test or a layout decision.
    public var isEmpty: Bool {
        toasts.isEmpty
    }
}
