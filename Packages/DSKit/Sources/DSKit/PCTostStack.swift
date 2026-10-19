//
//  PCTostStack.swift
//  DSKit
//
//  Created by Oleg Bragin on 02.10.2026.
//

import Observation
import SwiftUI

/// One toast: a message, an optional action, and how much of its window is left.
///
/// A value, so a stack holds toasts and not references to mutable screens. The action is a
/// closure rather than a route because the toasts that exist want different things — Undo
/// replays a delete, Retry replays a write — and neither is expressible as a destination.
///
/// **This is the name the type had as `PCTost`, renamed.** It sat beside the presenter called
/// `PCToast` with one letter between them, which is the worst possible distance when a screen
/// holds both at once — and now it does. `PCToast` is the thing, `PCToastPresenter` is the
/// thing that puts things in a stack.
public struct PCToast: Identifiable, Equatable {
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

    /// How much of the toast's window is left, or `nil` when it has no window at all.
    ///
    /// Optional rather than a `0` sentinel, and the distinction is the whole point: a failed
    /// save passes `nil` because it must not fade unattended, since it is the only notice that
    /// the user's work is not on disk. A `0` here would mean "the window has already closed"
    /// and would draw an empty bar — which reads as *this is over* on a toast that is precisely
    /// the one thing that is not over. `nil` draws no bar at all.
    ///
    /// It counts **up**, not down: the archive window's bar fills as its window elapses. It is
    /// written by the feature's own countdown, not computed here — see `PCTostStack.update`.
    public var progress: Double?

    public init(
        id: UUID = UUID(),
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        identifier: String = "pc-toast",
        actionIdentifier: String = "pc-toast-action",
        progress: Double? = nil
    ) {
        self.id = id
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.identifier = identifier
        self.actionIdentifier = actionIdentifier
        self.progress = progress
    }

    public static func == (lhs: PCToast, rhs: PCToast) -> Bool {
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
/// **Not** the owner of when a toast goes away. Each feature decides *when* to raise one and
/// *when* it is done; this only holds them. That split is what lets the stack live at the top of
/// the screen: the feature publishes, and a presenter far above the navigation draws it.
///
/// **It carries no timer, deliberately.** An earlier version of this type scheduled its own
/// removal from a `duration` and drew its own countdown, on the reasoning that a second timer
/// would be a second source of truth for when a toast goes away. That reasoning was right about
/// the timer and it was applied to the wrong code: the feature already owns one. The archive
/// window is a `PCTimeoutProgress` inside `CalendarListStore`, whose completion is what clears
/// `isArchiveToastPresented`. A timer here would race it, and the loser's toast would vanish a
/// frame or a window before the winner's — or, under load, the bar would hit empty while the
/// Undo the user is reaching for is still live. So the countdown stays with the feature and the
/// stack only draws what it is told.
@MainActor
@Observable
public final class PCToastStack {
    /// The pending toasts, oldest first — the order they are drawn in, so the newest is
    /// closest to the edge the user looks at last.
    public private(set) var toasts: [PCToast] = []

    /// The longest a stack is allowed to get. Toasts stack because two are occasionally
    /// true at once, not because a screen accumulates them; an unbounded stack would grow
    /// off-screen and cover the very content the messages are about.
    public var capacity = 3

    public init() {}

    /// Adds a toast, dropping the oldest if the stack is over capacity.
    ///
    /// Over-capacity drops the **oldest**, not the newest. A new message is the one the user
    /// just caused and is most likely to still care about; the oldest is the one whose window
    /// was about to close anyway.
    public func present(_ toast: PCToast) {
        toasts.append(toast)

        if toasts.count > capacity {
            toasts.removeFirst(toasts.count - capacity)
        }
    }

    /// Removes one toast. The action does not run: dismissal and activation are separate, so a
    /// toast that goes away on its own is gone without the user having pressed it.
    public func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    /// **No `dismissAll`, on purpose.** It existed on this type when the stack was unused and
    /// it has no caller now that it is not. With a shared stack it would also be a trap: the
    /// obvious-looking `dismissAll()` in a presenter's teardown takes every *other*
    /// presenter's toast with it, clearing a Retry because an archive window happened to
    /// close. A presenter dismisses by `id`, which is the only removal that means "mine".
    ///
    /// The one case that would want it — a screen tearing its toasts down — does not need it:
    /// the stack is `@State` on the screen, so it dies with the screen.

    /// Moves a presented toast's window along.
    ///
    /// The presenter calls this as the owning countdown advances, which is what keeps the bar
    /// and the feature's own state in step. Writing it into the observable stack rather than
    /// passing a closure through to the view is what makes the bar *move*: the draw reads
    /// `toasts`, so a changed `progress` here is a change SwiftUI re-renders. A closure stored
    /// in the toast would have captured the value from whichever render created it, and the bar
    /// would have frozen at whatever that was.
    ///
    /// A no-op for an unknown `id`, so a tick that lands after the toast was dismissed cannot
    /// bring it back.
    public func update(_ id: UUID, progress: Double?) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        toasts[index].progress = progress
    }

    /// Whether any toast is showing, for a layout decision.
    public var isEmpty: Bool {
        toasts.isEmpty
    }
}
