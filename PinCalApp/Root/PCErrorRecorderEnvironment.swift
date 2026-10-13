//
//  PCErrorRecorderEnvironment.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 12.10.2026.
//

import SwiftUI
import CorePersistence

extension EnvironmentValues {
    /// Where a view hands failures it has been told about.
    ///
    /// Injected rather than passed as a parameter because the failures arrive deep inside feature
    /// packages' views — the calendar list and the single calendar each raise theirs in a place
    /// that knows nothing about the app — and threading a parameter down to those sites would put
    /// a diagnostics concern in the signature of two unrelated screens.
    ///
    /// The default discards, so nothing breaks where it has not been provided.
    @Entry var pcErrorRecorder: PCErrorRecorder = .init(reporter: NoopPCErrorReporter())

    /// The table itself, for a screen that reads it.
    ///
    /// Separate from `pcErrorRecorder`, which only ever writes. Keeping the two apart means the
    /// recorder cannot be handed to a view that wanted to read, and a screen cannot record
    /// something while presenting a list of what has already failed.
    @Entry var pcErrorReporting: any PCErrorReporting = NoopPCErrorReporter()
}
