//
//  PCColorOptionNames.swift
//  SingleCalendarFeature
//

import DSKit

/// How `DSKit`'s colour options are called, resolved from the app's string catalog.
///
/// `DSKit` does not localize — its picker takes this as a parameter — so the words belong to
/// whichever feature puts a picker on screen. This is the single definition for all four call
/// sites, so the compact picker, the expanded picker and the sheet behind them cannot name the
/// same colour differently.
///
/// The `switch` is exhaustive over `PCColorOption`, which is the whole point: adding a fifth
/// colour is a compile error here rather than a blank label on screen. A
/// `[PCColorOption: String]` lookup would compile in that case and fail silently, which is the
/// same failure mode the function-based `PCColorOptionNames` exists to avoid.
///
/// `String(localized:)` rather than `NSLocalizedString` because it takes a string *literal*, and a
/// literal is what makes the key discoverable: Xcode extracts these into `pcLocalisation.xcstrings`
/// at build time, so adding a colour adds its label with nothing else to remember. It cannot be
/// used with a computed key, which is why the mapping is a switch and not a lookup table.
func pcColorOptionNames() -> PCColorOptionNames {
    PCColorOptionNames { option in
        switch option {
        case .option1: return String(localized: .option1)
        case .option2: return String(localized: .option2)
        case .option3: return String(localized: .option3)
        case .option4: return String(localized: .option4)
        }
    }
}
