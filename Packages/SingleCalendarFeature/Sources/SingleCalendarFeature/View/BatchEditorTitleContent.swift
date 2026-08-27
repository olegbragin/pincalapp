//
//  BatchEditorTitleContent.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

public struct BatchEditorTitleContent: View {
    var preferredTitle: String?
    var compactTitle: String?

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            BatchEditorPreferredTitle(title: preferredTitle)
            BatchEditorCompactTitle(title: compactTitle)
        }
    }
}

#Preview("Full Title") {
    BatchEditorTitleContent(preferredTitle: "Women Cycle", compactTitle: "Women Cycle")
}

#Preview("Compact Title") {
    BatchEditorTitleContent(preferredTitle: "A Very Long Batch Title That Should Be Compact", compactTitle: "A Very Long Batch Title")
}
