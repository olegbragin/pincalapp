//
//  PCColorPickerView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 24.02.2026.
//

import SwiftUI

struct PCColorPickerView: View {
    enum Style {
        case compact
        case expanded
    }
    
    @Binding var selectedColor: PCColorOption?
    var style: Style = .compact
    var defaultColor: PCColorOption? = nil
    
    var body: some View {
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
