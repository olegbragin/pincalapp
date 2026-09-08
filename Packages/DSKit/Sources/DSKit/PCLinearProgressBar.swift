//
//  PCLinearProgressBar.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import SwiftUI

/// A horizontal progress bar with a configurable "active" (filled) and
/// "remaining" (track) color. Pure SwiftUI, so it renders on every platform.
public struct PCLinearProgressBar: View {
    private let progress: Double
    private let activeColor: Color
    private let remainingColor: Color
    private let height: CGFloat

    public init(
        progress: Double,
        activeColor: Color,
        remainingColor: Color,
        height: CGFloat = 4
    ) {
        self.progress = progress
        self.activeColor = activeColor
        self.remainingColor = remainingColor
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(remainingColor)
                Capsule()
                    .fill(activeColor)
                    .frame(width: max(0, min(1, progress)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.1), value: progress)
    }
}

#Preview {
    VStack(spacing: 20) {
        PCLinearProgressBar(progress: 0.2, activeColor: .blue, remainingColor: Color.blue.opacity(0.2))
        PCLinearProgressBar(progress: 0.6, activeColor: .green, remainingColor: Color.green.opacity(0.2))
        PCLinearProgressBar(progress: 1, activeColor: .red, remainingColor: Color.red.opacity(0.2))
    }
    .padding()
}
