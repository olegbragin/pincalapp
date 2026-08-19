import SwiftUI

struct PCCalendarDayEventView: View {
    var events: [Color]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(events.indices, id: \.self) { index in
                Rectangle()
                    .fill(events[index])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    PCCalendarDayEventView(events: [
        .red, .green, .blue
    ])
}
