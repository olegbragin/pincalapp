import Testing
import SwiftUI
import DSKit

@Suite("PCVibe Tests")
struct PCVibeTests {

    @Test("default vibe has the default id and name")
    func defaultIdentity() {
        #expect(PCVibe.default.id == "default")
        #expect(PCVibe.default.name == "Default")
    }

    @Test("all contains the default vibe")
    func allContainsDefault() {
        #expect(PCVibe.all.contains(.default))
    }

    @Test("event colors map from options")
    func eventColors() {
        #expect(PCVibe.default.eventColor(for: .option1) == PCVibe.default.color(for: .eventOption1))
        #expect(PCVibe.default.eventColor(named: PCColorOption.option2.colorName) == PCVibe.default.color(for: .eventOption2))
        #expect(PCVibe.default.eventColor(named: "unknown") == .clear)
    }

    @Test("unknown roles fall back to clear")
    func unknownRoleFallsBackToClear() {
        let vibe = PCVibe(id: "test", name: "Test", colors: [:])
        #expect(vibe.color(for: .background) == .clear)
    }
}
