//
//  DeviceOrientation.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.08.2026.
//

import SwiftUI

private struct DeviceOrientationViewModifier: ViewModifier {
    @Binding var isLandscape: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            isLandscape = proxy.size.width > proxy.size.height
                        }
                        .onChange(of: proxy.size) { _, size in
                            isLandscape = size.width > size.height
                        }
                }
            )
    }
}

extension View {
    func deviceOrientation(_ isLandscape: Binding<Bool>) -> some View {
        modifier(DeviceOrientationViewModifier(isLandscape: isLandscape))
    }
}
