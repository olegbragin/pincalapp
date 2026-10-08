//
//  PCAlert.swift
//  DSKit
//

import SwiftUI

/// One button in a `PCAlert`.
///
/// The action is stored rather than passed to the modifier, so the alert is a *value* a view can
/// build and hand over rather than a set of callbacks the modifier has to be told about
/// separately. That is what lets one presentation site serve every alert in the app: it never
/// knows what any particular alert is for.
public struct PCAlertButton: Identifiable {
    public let id = UUID()

    /// What the user reads.
    public let title: String

    /// `nil` for an ordinary button. `.cancel` and `.destructive` are how iOS decides which one
    /// a keyboard's Return key activates and how it is styled, so this is worth threading through
    /// rather than treating as decoration — a destructive action shown as a plain button is a
    /// mis-click waiting to happen.
    public let role: ButtonRole?

    /// Called when tapped. Runs before the alert dismisses.
    public let action: () -> Void

    public init(title: String, role: ButtonRole? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.action = action
    }

    /// A button that only dismisses.
    public static func dismiss(title: String) -> PCAlertButton {
        PCAlertButton(title: title, role: .cancel)
    }
}

/// What an alert says, as a value.
///
/// Title, body and buttons — which is the whole of what iOS takes, so there is no fourth thing
/// to configure and nothing here that a future iOS version could invalidate.
public struct PCAlertContent {
    public let title: String
    public let message: String
    public let buttons: [PCAlertButton]

    /// `nil` when there are no buttons would leave iOS with nothing to dismiss the alert, so an
    /// empty list is rejected rather than shown: an alert the user cannot close is a screen they
    /// are stuck on.
    public init(title: String, message: String, buttons: [PCAlertButton]) {
        precondition(!buttons.isEmpty, "a PCAlert with no buttons cannot be dismissed")
        self.title = title
        self.message = message
        self.buttons = buttons
    }

    /// The common shape: something went wrong, acknowledge it.
    public init(title: String, message: String, dismiss: String) {
        self.init(title: title, message: message, buttons: [.dismiss(title: dismiss)])
    }
}

public extension View {
    /// Presents `alert` when it is not `nil`, and dismisses it by setting the binding to `nil`.
    ///
    /// The binding is to the *whole* alert rather than to a `Bool` beside a separate content
    /// value, because two pieces of state cannot disagree: there is no state in which this says
    /// "presented" while the text is something else.
    ///
    /// The alert must be presented from the root of a screen rather than from inside the thing
    /// that raised it — an alert attached to a view inside a `navigationDestination` is presented
    /// by that destination, so a switch away from it takes the alert with it and the failure it
    /// was reporting is never seen.
    func pcAlert(_ alert: Binding<PCAlertContent?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { alert.wrappedValue != nil },
                set: {
                    if !$0 {
                        alert.wrappedValue = nil
                    }
                }
            ),
            presenting: alert.wrappedValue
        ) { content in
            // Indexed rather than keyed by title: two buttons may legitimately share a title, and
            // `ForEach` needs identities that are distinct for reasons unrelated to their labels.
            ForEach(0..<content.buttons.count, id: \.self) { index in
                let button = content.buttons[index]
                Button(button.title, role: button.role, action: button.action)
            }
        } message: { content in
            Text(verbatim: content.message)
        }
    }
}
