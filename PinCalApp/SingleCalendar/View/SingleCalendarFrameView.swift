//
//  SingleCalendarFrameView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 19.08.2026.
//

import SwiftUI

struct SingleCalendarFrameView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SingleCalendarFrameView {
        Text("Calendar Content")
    }
}
