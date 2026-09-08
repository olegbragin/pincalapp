import Testing
import SwiftUI
import SettingsFeature

@Suite("AppTheme Tests")
struct AppThemeTests {

    @Test("titles match the expected labels")
    func titles() {
        #expect(AppTheme.system.title == "System")
        #expect(AppTheme.light.title == "Always light")
        #expect(AppTheme.dark.title == "Always dark")
    }

    @Test("colorScheme maps to the right scheme")
    func colorScheme() {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    @Test("raw value round-trips")
    func rawValueRoundTrip() {
        for theme in AppTheme.allCases {
            #expect(AppTheme(rawValue: theme.rawValue) == theme)
        }
    }
}
