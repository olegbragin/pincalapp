//
//  PCColorPickerView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.02.2026.
//

import SwiftUI

public struct PCColorPickerView: View {
    public enum Style {
        case compact
        case expanded
    }
    
    @Binding var selectedColor: PCColorOption?
    public var style: Style = .compact
    public var defaultColor: PCColorOption? = nil

    public init(selectedColor: Binding<PCColorOption?>, style: Style = .compact, defaultColor: PCColorOption? = nil) {
        self._selectedColor = selectedColor
        self.style = style
        self.defaultColor = defaultColor
    }
    
    public var body: some View {
        switch style {
        case .compact:
            PCCompactColorPicker(selectedColor: $selectedColor, defaultColor: defaultColor)
        case .expanded:
            PCExpandedColorPicker(selectedColor: $selectedColor, defaultColor: defaultColor)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PCColorPickerView(selectedColor: .constant(.option1))
        PCColorPickerView(selectedColor: .constant(.option2), style: .expanded)
    }
}