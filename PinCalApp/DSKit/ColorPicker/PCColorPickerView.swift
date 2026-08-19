//
//  ColorPickerView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.02.2026.
//

import SwiftUI

struct ColorPickerView: View {
    enum Style {
        case compact
        case expanded
    }
    
    @Binding var selectedColor: ColorOption?
    var style: Style = .compact
    var defaultColor: ColorOption? = nil
    
    var body: some View {
        switch style {
        case .compact:
            CompactColorPicker(selectedColor: $selectedColor, defaultColor: defaultColor)
        case .expanded:
            ExpandedColorPicker(selectedColor: $selectedColor, defaultColor: defaultColor)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        ColorPickerView(selectedColor: .constant(.option1))
        ColorPickerView(selectedColor: .constant(.option2), style: .expanded)
    }
}
