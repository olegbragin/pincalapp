import Foundation
import SwiftUI

extension String {
    static func localized(_ key: String, _ arguments: any CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: "pcScfLocalisation", bundle: .module, comment: "")
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
