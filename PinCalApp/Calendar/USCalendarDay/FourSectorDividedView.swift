//
//  FourSectorDividedView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 17.03.2026.
//

import SwiftUI

struct FourSectorDividedView: View {
    var events: [Color]
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            
            // Точки углов квадрата
            let topLeft = CGPoint(x: 0, y: 0)
            let topRight = CGPoint(x: size.width, y: 0)
            let bottomLeft = CGPoint(x: 0, y: size.height)
            let bottomRight = CGPoint(x: size.width, y: size.height)
            
            // Сектор 1 (верхний левый) — от центра к верхнему левому углу, затем к границам
            let path1 = Path { path in
                path.move(to: center)
                path.addLine(to: topLeft)
                path.addLine(to: bottomLeft) // середина левой грани
                path.closeSubpath()
            }
            context.fill(path1, with: .color(events[0]))
            
            // Сектор 2 (верхний правый) — от центра к верхнему правому углу, затем к границам
            let path2 = Path { path in
                path.move(to: center)
                path.addLine(to: topRight)
                path.addLine(to: topLeft) // середина верхней грани
                path.closeSubpath()
            }
            context.fill(path2, with: .color(events[1]))
            
            // Сектор 3 (нижний левый) — от центра к нижнему левому углу, затем к границам
            let path3 = Path { path in
                path.move(to: center)
                path.addLine(to: bottomLeft)
                path.addLine(to: bottomRight) // середина левой грани
                path.closeSubpath()
            }
            context.fill(path3, with: .color(events[2]))
            
            // Сектор 4 (нижний правый) — от центра к нижнему правому углу, затем к границам
            let path4 = Path { path in
                path.move(to: center)
                path.addLine(to: bottomRight)
                path.addLine(to: topRight) // середина нижней грани
                path.closeSubpath()
            }
            context.fill(path4, with: .color(events[3]))
        }
    }
}

#Preview {
    FourSectorDividedView(events: [
        .red, .brown, .green, .blue
    ])
}
