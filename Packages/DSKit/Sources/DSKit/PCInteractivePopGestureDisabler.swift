//
//  PCInteractivePopGestureDisabler.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 16.09.2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit

/// Disables the navigation controller's interactive pop (edge-swipe-back) gesture
/// so a horizontal swipe inside the content isn't hijacked as "go back", while
/// keeping the toolbar Back button fully functional.
///
/// Applied to screens that host a horizontally-swipeable view (e.g. the calendar's
/// year-swipe). The system's edge-swipe-back is a UIKit gesture that SwiftUI
/// gestures cannot reliably preempt, so the only reliable option is to turn the
/// interactive pop gesture off for the navigation stack that contains the screen.
private struct PCInteractivePopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }
}

public extension View {
    /// Disables the interactive pop (edge-swipe-back) gesture for the navigation
    /// stack hosting this view. The toolbar Back button still works; only the
    /// swipe-to-go-back gesture is turned off, so horizontal swipes on the
    /// calendar's year grid aren't mistaken for a navigation pop.
    @ViewBuilder
    func pcDisableInteractivePopGesture() -> some View {
        background(PCInteractivePopGestureDisabler())
    }
}
#endif
