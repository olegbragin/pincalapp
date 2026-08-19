//
//  BatchEditorCompactTitle.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct BatchEditorCompactTitle: View {
    var title: String?

    var body: some View {
        if let title {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

#Preview("With Title") {
    BatchEditorCompactTitle(title: "A Very Long Batch Title")
}

#Preview("Without Title") {
    BatchEditorCompactTitle(title: nil)
}
