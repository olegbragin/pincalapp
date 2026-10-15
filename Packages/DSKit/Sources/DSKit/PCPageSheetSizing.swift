//
//  PCPageSheetSizing.swift
//  DSKit
//
//  Created by Oleg Bragin on 15.10.2026.
//

import SwiftUI

/// Presents its content as a page sheet — one that covers the window — where the OS
/// supports asking for it.
///
/// The package deploys to iOS 17 and `.presentationSizing` arrived in iOS 18, so this is
/// gated rather than used directly. On iOS 17 the modifier does nothing and the sheet
/// presents as whatever the system chooses, which is the behaviour that predates this work.
///
/// A `ViewModifier` rather than an `if #available` in the view body: the presentation
/// modifier has to be applied to the sheet's content, and there is no way to write
/// `content.modifier(a) : content.modifier(b)` on one line without a type-erasing wrapper
/// that costs more than this does.
public struct PCPageSheetSizing: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
