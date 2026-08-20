//
//  RootContentView.swift
//  PinCalApp
//

import SwiftUI

struct RootContentView: View {
    @Binding var navigation: RootNavigation

    var body: some View {
        CalendarListView(navigation: $navigation)
    }
}
