//
//  USCalendarWeekHeaderView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import SwiftUI

struct USCalendarWeekHeaderView: View {
    @Bindable var viewModel: USCalendarWeekHeaderModel
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.weekSymbols, id: \.id) { symbol in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.clear)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(2)
                    
                    Text(symbol.name)
                        .font(.footnote)
                        .foregroundColor(Color("colorForegroundDisabled"))
                        .background(.clear)
                        .shadow(radius: 2)
                }
            }
        }
    }
}

#Preview {
    USCalendarWeekHeaderView(viewModel: .init(weekSymbols: [
        "S", "T"
    ]))
}
