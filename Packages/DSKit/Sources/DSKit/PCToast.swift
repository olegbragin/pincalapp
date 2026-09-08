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

    public init(
        isPresented: Binding<Bool>,
        position: PCToastPosition = .bottom,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        backgroundColor: Color,
        progress: Double,
        progressActiveColor: Color = .white,
        progressRemainingColor: Color = .white.opacity(0.3)
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
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
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
        progressRemainingColor: Color = .white.opacity(0.3)
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
                progressRemainingColor: progressRemainingColor
            )
        )
    }
}
