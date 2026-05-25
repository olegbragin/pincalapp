import SwiftUI
import CoreGraphics

struct USCalendarDayEventView: View {
    var events: [Color]
    
    var body: some View {
        switch events.count {
        case 1:
            RoundedRectangle(cornerRadius: 8)
                .fill(events[0])
        case 2:
            TwoSectorDividedView(events: events)
        case 3:
            ThreeSectorDividedView(events: events)
        case 4:
            FourSectorDividedView(events: events)
        default:
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: events,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

#Preview {
    USCalendarDayEventView(events: [
        .red, .green, .blue
    ])
}
