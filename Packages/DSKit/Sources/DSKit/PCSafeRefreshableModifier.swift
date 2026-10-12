//
//  PCSafeRefreshableModifier.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 17.08.2026.
//

import SwiftUI

/// A ViewModifier that provides pull-to-refresh behavior.
/// On iOS 26+, uses a custom DragGesture-based implementation to work around
/// a SwiftUI bug where `.refreshable` on `ScrollView` causes contentOffset jumps.
/// On older iOS versions, uses the standard `.refreshable` modifier.
public struct PCSafeRefreshableModifier: ViewModifier {
    /// Throws, and that is the point of the change.
    ///
    /// It was `() async -> Void`, which made a failing refresh **inexpressible rather than merely
    /// unhandled**: the only thing a caller could do with a thrown error was swallow it, so a
    /// refresh that hit a database error looked exactly like one that succeeded. The list it
    /// refreshes then showed whatever the failure left behind, with no indication anything was
    /// wrong.
    let refreshAction: @Sendable () async throws -> Void

    /// Called when a refresh fails, if the caller supplied one.
    ///
    /// Optional because this modifier has no user-facing vocabulary of its own — it is a
    /// gesture, not a screen. What to say about a failed refresh belongs to whoever owns the
    /// list, the same split `PCSafeRefreshable` has always had with its presentation.
    var onRefreshFailed: (@Sendable (any Error) -> Void)?

    @State private var isRefreshing = false
    @State private var dragOffset: CGFloat = 0

    public func body(content: Content) -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .offset(y: dragOffset)
                    .overlay(alignment: .top) {
                        ProgressView()
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .opacity(isRefreshing ? 1 : min(1, dragOffset / 30))
                            .animation(.easeOut(duration: 0.15), value: dragOffset)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12, coordinateSpace: .local)
                            .onChanged { value in
                                guard !isRefreshing else { return }
                                let vertical = value.translation.height
                                let horizontal = value.translation.width
                                guard vertical > 0, vertical > abs(horizontal) else { return }
                                withAnimation(.easeOut(duration: 0.15)) {
                                    dragOffset = vertical * 0.5
                                }
                            }
                            .onEnded { value in
                                guard !isRefreshing else { return }
                                let vertical = value.translation.height
                                let horizontal = value.translation.width
                                guard vertical > 0, vertical > abs(horizontal) else {
                                    if dragOffset > 0 {
                                        withAnimation(.spring(response: 0.35)) { dragOffset = 0 }
                                    }
                                    return
                                }
                                if dragOffset > 10 {
                                    Task { await triggerRefresh() }
                                } else {
                                    withAnimation(.spring(response: 0.35)) { dragOffset = 0 }
                                }
                            }
                    )
            } else {
                content
                    .refreshable { try? await refreshAction() }
            }
        #else
            content
                .refreshable { try? await refreshAction() }
        #endif
    }

    /// Runs the refresh, reports a failure, and always puts the spinner away.
    ///
    /// The failure is reported *and* the UI is restored, because both were wrong before: a
    /// swallowed error left the user looking at a stale list with no explanation, and letting the
    /// throw escape would have left `isRefreshing` stuck true with the indicator spinning
    /// forever — a worse failure than the one that caused it.
    private func triggerRefresh() async {
        guard !isRefreshing else { return }
        withAnimation(.spring(response: 0.35)) {
            isRefreshing = true
            dragOffset = 64
        }
        do {
            try await refreshAction()
        } catch {
            onRefreshFailed?(error)
        }
        // Only reached on success or after the failure has been reported — never skipped, so
        // the spinner cannot be stranded by a throw.
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.spring(response: 0.35)) {
            isRefreshing = false
            dragOffset = 0
        }
    }
}

public extension View {
    /// Adds pull-to-refresh behavior. On iOS 26+, uses a custom implementation
    /// to work around a SwiftUI `.refreshable` bug. On older iOS versions, uses
    /// the standard `.refreshable`.
    ///
    /// Prefer this over `.refreshable` for any scrollable list. Plain
    /// `.refreshable` on a `ScrollView` is what triggers the contentOffset jump on
    /// iOS 26+, and the workaround is worth reaching for by default rather than
    /// per-screen.
    ///
    /// `action` throws so a failed refresh can be told from a successful one. Supply
    /// `onRefreshFailed` to hear about the failure — without it the error is discarded, and
    /// discarding it is exactly what the non-throwing signature used to make unavoidable.
    func safeRefreshable(
        action: @escaping @Sendable () async throws -> Void,
        onRefreshFailed: (@Sendable (any Error) -> Void)? = nil
    ) -> some View {
        modifier(
            PCSafeRefreshableModifier(
                refreshAction: action,
                onRefreshFailed: onRefreshFailed
            )
        )
    }
}
