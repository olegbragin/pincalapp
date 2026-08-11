import SwiftUI

struct USCalendarDayEventView: View {
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
    USCalendarDayEventView(events: [
        .red, .green, .blue
    ])
}
