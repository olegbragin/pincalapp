//
//  SwiftUIView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 17.03.2026.
//

import SwiftUI

struct ThreeSectorDividedView: View {
    var events: [Color]
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Точки для разделителей
            let topMid = CGPoint(x: size.width / 2, y: 0) // середина верхней грани
            let bottomLeft = CGPoint(x: 0, y: size.height) // левый нижний угол
            let bottomRight = CGPoint(x: size.width, y: size.height) // правый нижний угол


            // Сектор 1 (верхний) — от центра к верхней середине, затем к углам нижней грани
            let path1 = Path { path in
                path.move(to: center)
                path.addLine(to: bottomRight)
                path.addLine(to: bottomLeft)
                path.closeSubpath()
            }
            context.fill(path1, with: .color(events[0]))


            // Сектор 2 (левый) — от центра к левому нижнему углу, затем к верхней грани и центру
            let path2 = Path { path in
                path.move(to: center)
                path.addLine(to: bottomLeft)
                path.addLine(to: CGPoint(x: 0, y: 0)) // левый верхний угол
                path.addLine(to: topMid)
                path.closeSubpath()
            }
            context.fill(path2, with: .color(events[1]))


            // Сектор 3 (правый) — от центра к правому нижнему углу, затем к верхней грани и центру
            let path3 = Path { path in
                path.move(to: center)
                path.addLine(to: bottomRight)
                path.addLine(to: CGPoint(x: size.width, y: 0)) // правый верхний угол
                path.addLine(to: topMid)
                path.closeSubpath()
            }
            context.fill(path3, with: .color(events[2]))
        }
    }
}

#Preview {
    ThreeSectorDividedView(events: [
        .red, .green, .blue
    ])
}
