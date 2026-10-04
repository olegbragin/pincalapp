
import Observation
import CoreDomain

@Observable
public final class AddEditCalendarViewModel {
    var id: Int64 = 0
    var label: String = ""
    var calendar: PinCalendar?

    func save() -> Bool {
        guard !label.isEmpty else { return false }
        calendar = PinCalendar(id: id, name: label, year: 2026, numberOfColumns: 1)
        return true
    }

    func reset() {
        id = 0
        label = ""
        calendar = nil
    }
}
