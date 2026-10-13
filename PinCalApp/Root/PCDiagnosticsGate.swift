//
//  PCDiagnosticsGate.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import Foundation

/// Whether the Diagnostics screen is available in this build.
///
/// An Info.plist key rather than a runtime guess. The common alternative — inspecting
/// `Bundle.main.appStoreReceiptURL` for `sandboxReceipt` — is the community heuristic for "am I on
/// TestFlight", and it is not an API Apple documents. It also answers the wrong question: this
/// screen is about *who is allowed to see it*, which is a property of the build someone shipped,
/// not something to infer at runtime.
///
/// The key is set per configuration. Absent means off, so forgetting it on a release build leaves
/// the screen hidden rather than exposed — the failure of the two directions that actually happens.
///
/// What this is **not** is a security control. Anyone who can install the app can edit its
/// Info.plist. It is a way of not shipping a debug surface in the App Store build, which is a
/// review and tidiness concern, not a defence.
enum PCDiagnosticsGate {
    /// The Info.plist key. Read here once so the string is not spelled out at each use.
    static let infoPlistKey = "PCDiagnosticsEnabled"

    static var isAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? Bool ?? false
    }
}
