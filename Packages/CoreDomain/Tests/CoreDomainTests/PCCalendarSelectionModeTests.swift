import Testing
import CoreDomain

@Suite("PCCalendarSelectionMode Tests")
struct PCCalendarSelectionModeTests {

    @Test("Cases are distinct and equatable")
    func casesAreDistinct() {
        #expect(PCCalendarSelectionMode.single == .single)
        #expect(PCCalendarSelectionMode.single != .multiple)
        #expect(PCCalendarSelectionMode.multiple == .multiple)
    }

    @Test("Switch exhaustively handles the two supported modes")
    func switchHandlesBothCases() {
        func modeName(_ mode: PCCalendarSelectionMode) -> String {
            switch mode {
            case .single: return "single"
            case .multiple: return "multiple"
            }
        }

        #expect(modeName(.single) == "single")
        #expect(modeName(.multiple) == "multiple")
    }
}