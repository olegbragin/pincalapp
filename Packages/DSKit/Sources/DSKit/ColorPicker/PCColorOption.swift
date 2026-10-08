//
//  PCColorOption.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

/// A colour the user can pick. `Equatable` because it is held in the batch-assembly
/// state, which is compared with `==` to decide whether a transition changed anything
/// (`PCEventSelectionManager.send`). Without it a state carrying a colour could not be
/// `Equatable`, and the whole store would have to be split across stages. `Hashable`
/// because a `PCEventBatchAssembleUnitOfWork` treats colour identity as a value, not a reference.
public enum PCColorOption: CaseIterable, Equatable, Hashable {
    case option1,
         option2,
         option3,
         option4

    /// The colour a new batch starts on.
    ///
    /// Named rather than spelled as `.option1` at each call site, because "the first colour
    /// the picker offers" is a product decision that has exactly one answer and several
    /// places that need it. Before this existed a new batch had *no* colour, so its Save was
    /// disabled and the user had to go looking for the picker to do anything at all.
    public static var firstAvailable: PCColorOption {
        .option1
    }

    public var colorName: String {
        switch self {
        case .option1: return "eventColorOption1"
        case .option2: return "eventColorOption2"
        case .option3: return "eventColorOption3"
        case .option4: return "eventColorOption4"
        }
    }

    public init?(_ rawValue: String) {
        switch rawValue {
        case "eventColorOption1":
            self = .option1
        case "eventColorOption2":
            self = .option2
        case "eventColorOption3":
            self = .option3
        case "eventColorOption4":
            self = .option4
        default:
            return nil
        }
    }
}

/// How each colour option is called, supplied by whoever owns the words.
///
/// A value rather than four parallel string properties so a caller threads one thing through
/// `PCColorPickerView`, `PCExpandedColorPicker` and `PCColorOptionSheet` instead of three sets of
/// arguments that can drift apart. A function rather than a `[PCColorOption: String]` because a
/// dictionary can be *missing* an entry, and a missing entry draws an empty label that no
/// compiler complains about — the silent half of a localization bug.
///
/// `Sendable` because the pickers are values that cross the concurrency boundary Swift 6 draws
/// around a view's captured state.
public struct PCColorOptionNames: Sendable {
    private let name: @Sendable (PCColorOption) -> String

    public init(_ name: @escaping @Sendable (PCColorOption) -> String) {
        self.name = name
    }

    public func name(for option: PCColorOption) -> String {
        name(option)
    }
}
