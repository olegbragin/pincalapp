//
//  PCKeyboardState.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.08.2026.
//

import UIKit
import Observation

@MainActor
@Observable
final class PCKeyboardState {

    private(set) var keyboardHeight: CGFloat = 0

    var isVisible: Bool { keyboardHeight > 0 }

    private nonisolated(unsafe) var notificationTokens: [NSObjectProtocol] = []

    init() {
        let notificationCenter = NotificationCenter.default
        notificationTokens.append(
            notificationCenter.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let endFrameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
                    return
                }
                let keyboardFrame = endFrameValue.cgRectValue
                MainActor.assumeIsolated {
                    self?.process(keyboardFrame: keyboardFrame)
                }
            }
        )
    }

    private func process(keyboardFrame: CGRect) {
        guard let window = Self.keyWindow else { return }
        let visibleHeight = max(0, window.bounds.maxY - keyboardFrame.minY)
        keyboardHeight = min(visibleHeight, window.bounds.height)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }
}
