//
//  BatchEditorPreferredTitle.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct BatchEditorPreferredTitle: View {
    var title: String?

    var body: some View {
        if let title {
            Text(title)
                .font(.headline)
                .lineLimit(1)
        }
    }
}

#Preview("With Title") {
    BatchEditorPreferredTitle(title: "Women Cycle")
}

#Preview("Without Title") {
    BatchEditorPreferredTitle(title: nil)
}
