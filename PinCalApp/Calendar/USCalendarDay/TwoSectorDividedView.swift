//
//  2SectorDividedView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 17.03.2026.
//

import SwiftUI

struct TwoSectorDividedView: View {
    var events: [Color]
    var body: some View {
        Canvas { context, size in
            // Точки углов квадрата
            let bottomLeft = CGPoint(x: 0, y: size.height)      // нижний левый
            let topRight = CGPoint(x: size.width, y: 0)        // верхний правый
            let topLeft = CGPoint(x: 0, y: 0)                 // верхний левый
            let bottomRight = CGPoint(x: size.width, y: size.height) // нижний правый

            // Сектор 1 (левый/верхний) — треугольник от нижнего левого к верхнему правому и верхнему левому углу
            let path1 = Path { path in
                path.move(to: bottomLeft)
                path.addLine(to: topRight)
                path.addLine(to: topLeft)
                path.closeSubpath()
            }
            context.fill(path1, with: .color(events[0]))

            // Сектор 2 (правый/нижний) — треугольник от нижнего левого к верхнему правому и нижнему правому углу
            let path2 = Path { path in
                path.move(to: bottomLeft)
                path.addLine(to: topRight)
                path.addLine(to: bottomRight)
                path.closeSubpath()
            }
            context.fill(path2, with: .color(events[1]))
        }
    }
}

#Preview {
    TwoSectorDividedView(events: [.red, .blue])
}
