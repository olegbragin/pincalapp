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
/// because a `BatchAssembler` treats colour identity as a value, not a reference.
public enum PCColorOption: CaseIterable, Equatable, Hashable {
    case option1,
         option2,
         option3,
         option4

    public var colorName: String {
        switch self {
        case .option1: return "eventColorOption1"
        case .option2: return "eventColorOption2"
        case .option3: return "eventColorOption3"
        case .option4: return "eventColorOption4"
        }
    }

    public var name: String {
        switch self {
        case .option1: return "Вариант 1"
        case .option2: return "Вариант 2"
        case .option3: return "Вариант 3"
        case .option4: return "Вариант 4"
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
