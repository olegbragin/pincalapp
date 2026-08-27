import SwiftUI

public struct PCDatePicker: View {
    let title: String
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents = [.hourAndMinute]

    public init(title: String, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute]) {
        self.title = title
        self._selection = selection
        self.displayedComponents = displayedComponents
    }

    public var body: some View {
        DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
    }
}