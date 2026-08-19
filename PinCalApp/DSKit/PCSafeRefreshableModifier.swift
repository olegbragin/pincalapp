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
struct PCSafeRefreshableModifier: ViewModifier {
    let refreshAction: @Sendable () async -> Void

    @State private var isRefreshing = false
    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
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
                .refreshable { await refreshAction() }
        }
    }

    private func triggerRefresh() async {
        guard !isRefreshing else { return }
        withAnimation(.spring(response: 0.35)) {
            isRefreshing = true
            dragOffset = 64
        }
        await refreshAction()
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.spring(response: 0.35)) {
            isRefreshing = false
            dragOffset = 0
        }
    }
}

extension View {
    /// Adds pull-to-refresh behavior. On iOS 26+, uses a custom implementation
    /// to work around a SwiftUI `.refreshable` bug. On older iOS versions, uses
    /// the standard `.refreshable`.
    func safeRefreshable(action: @escaping @Sendable () async -> Void) -> some View {
        modifier(PCSafeRefreshableModifier(refreshAction: action))
    }
}
