//
//  DeviceOrientation.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.08.2026.
//

import SwiftUI

/// The window shapes this file reasons about.
///
/// Expressed in points rather than in device names so the predicate below is a pure function
/// of a `CGSize` — no simulator, no `UIDevice`, and something a unit test can call directly.
enum PCWindowShape {
    /// Tallest window an iPhone can present in landscape.
    ///
    /// A Pro Max is 430-440pt tall in landscape, while the shortest iPad is 834pt in *portrait*.
    /// 500pt therefore sits in the gap between them with room to spare on both sides, which is
    /// what lets this be a height test rather than an idiom test: `horizontalSizeClass` cannot
    /// separate a landscape Pro Max from a portrait iPhone (both are `.compact`, the sole size
    /// class read in the app, at `RootView.swift:28`), and `verticalSizeClass` would work only
    /// if this predicate were allowed to read the environment — which would make it untestable
    /// in isolation and unavailable to the non-view code that needs the same answer.
    static let tallestPhoneLandscapeHeight: CGFloat = 500

    /// Whether `size` is a landscape iPhone window — the shape where the three-column split
    /// view stops fitting and the detail column needs help.
    ///
    /// Height does the work, not width. A width test would also match iPad landscape, which is
    /// precisely the device whose three-column layout must not change; requiring the window to be
    /// both wide *and* short cannot match a tablet, because no tablet is ever this short.
    static func isPhoneLandscape(_ size: CGSize) -> Bool {
        size.width > size.height && size.height <= tallestPhoneLandscapeHeight
    }
}

private struct DeviceOrientationViewModifier: ViewModifier {
    @Binding var isLandscape: Bool

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            isLandscape = proxy.size.width > proxy.size.height
                        }
                        .onChange(of: proxy.size) { _, size in
                            isLandscape = size.width > size.height
                        }
                }
            )
    }
}

extension View {
    /// Pins the column to `railWidth` while `isCollapsed`, and stops constraining it otherwise.
    ///
    /// Conditional rather than `collapsed ? rail : someMeasuredWidth`, and that difference is the
    /// point. The expanded widths were removed from `RootView` because none of them had been
    /// measured — the only frames available came from a build that already carried width
    /// preferences, so there was no baseline for the unconstrained default to compare against.
    /// Hard-coding them would have been a guess dressed as a measurement, and it would have
    /// quietly reshaped the iPad and portrait-phone layouts that the suites are verified
    /// against. Leaving the modifier off when expanded keeps the app exactly as it was there.
    ///
    /// The detail passes `constrainDetail: true` and is therefore never pinned, even collapsed:
    /// every point the leading columns give up has to arrive somewhere, and a `max` on the
    /// detail would cap precisely the width the toggle exists to buy.
    ///
    /// **The column width does not animate, and cannot.** `navigationSplitViewColumnWidth` is a
    /// layout *preference* — the split view "does its best to accommodate the preferences that
    /// you specify, but might make other adjustments based on other constraints" — and it is
    /// resolved in the split view's own layout pass, outside the caller's transaction. Both
    /// `withAnimation` around the mutation and `.animation(_:value:)` on this modifier were
    /// tried and neither moved the column; the second was removed rather than left in place
    /// looking like a fix.
    ///
    /// `columnVisibility` is the animatable one — it is the system's own transition, which is
    /// why the sidebar toggle on iPad slides. It cannot be used here: `.doubleColumn` shows the
    /// content column at its own width, which is the layout that does not fit in the first
    /// place, and `.detailOnly` removes the calendar switcher entirely.
    ///
    /// So the snap is accepted. Animating it would mean owning the layout rather than hinting at
    /// it — an `HStack` in place of the split view for this one shape — which is a structural
    /// change to `RootView` and not a modifier away.
    func collapsedColumnWidth(_ isCollapsed: Bool, railWidth: CGFloat, isDetail: Bool = false) -> some View {
        modifier(CollapsedColumnWidthModifier(isCollapsed: isCollapsed, railWidth: railWidth, isDetail: isDetail))
    }
}

private struct CollapsedColumnWidthModifier: ViewModifier {
    let isCollapsed: Bool
    let railWidth: CGFloat
    let isDetail: Bool

    func body(content: Content) -> some View {
        if isCollapsed, !isDetail {
            content.navigationSplitViewColumnWidth(min: railWidth, ideal: railWidth, max: railWidth)
        } else {
            content
        }
    }
}

extension View {
    func deviceOrientation(_ isLandscape: Binding<Bool>) -> some View {
        modifier(DeviceOrientationViewModifier(isLandscape: isLandscape))
    }
}
