//
//  PCCalendarWeekHeaderView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import SwiftUI

public struct PCCalendarWeekHeaderView: View {
    @Bindable var viewModel: PCCalendarWeekHeaderModel
    var cellSize: CGFloat
    
    public var body: some View {
        GridRow {
            ForEach(viewModel.weekSymbols, id: \.id) { symbol in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.clear)
                        .padding(2)
                    
                    Text(symbol.name)
                        .font(.footnote)
                        .foregroundColor(Color("colorForegroundDisabled"))
                        .background(.clear)
                }
                .frame(width: cellSize, height: cellSize)
            }
        }
    }
}

#Preview {
    Grid {
        PCCalendarWeekHeaderView(
            viewModel: .init(weekSymbols: [
                "S", "T"
            ]),
            cellSize: 50
        )
    }
}