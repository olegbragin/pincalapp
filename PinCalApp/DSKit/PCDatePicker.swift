import SwiftUI

struct PCDatePicker: View {
    let title: String
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents = [.hourAndMinute]

    var body: some View {
        DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
    }
}
