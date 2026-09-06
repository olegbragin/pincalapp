//
//  PCColorOption+Color.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import SwiftUI
import CoreDomain

public extension PCColorOption {
    /// The concrete SwiftUI color for this option. Lives in DSKit because it
    /// depends on the design-system palette; the domain `PCColorOption` only
    /// carries the canonical `colorName`.
    var color: Color {
        switch self {
        case .option1: return Color.dsKit.colorEventOption1
        case .option2: return Color.dsKit.colorEventOption2
        case .option3: return Color.dsKit.colorEventOption3
        case .option4: return Color.dsKit.colorEventOption4
        }
    }
}
