
import SwiftUI
import AppNavigation
import CalendarListFeature
import DSKit
import SettingsFeature

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation
    @Environment(\.pcVibe) private var vibe

    var selectedCalendarID: Int64? {
        navigation.detailCalendarID
    }

    /// A calendar left the active set, so stop showing it.
    ///
    /// The list is where calendars are watched, so it is what hears about this; the navigation
    /// owns what is on screen and is the only thing that can decide the calendar is closed. The
    /// close is conditional on the id, so the two can be wired without either knowing what the
    /// other is for — this fires for every calendar that leaves the set, and only the one that
    /// was on screen is closed.
    ///
    /// `Task` because the close ends the calendar's multi-select session, which awaits the
    /// store. Same reason selecting a calendar is wrapped: the route change happens after an
    /// async step, not instead of one.
    private func closeIfSelected(_ id: Int64) {
        Task { await navigation.closeCalendarIfSelected(id) }
    }

    /// The rail shown when the columns are collapsed.
    ///
    /// A width preference can shrink the column but not remove it, so collapsed is a ~56pt
    /// strip rather than nothing. It has to carry its own way back: the toolbar button that
    /// collapsed this is on the list that is no longer on screen, so leaving the affordance to
    /// the toolbar would strand the user in a layout they cannot undo.
    ///
    /// **The button is in this column's toolbar, and the frame below is load-bearing.** Three
    /// arrangements were tried; the first two failed.
    ///
    /// An inline button was centred, which put it about a gutter-width right of the sidebar
    /// toggle. Aligning them exactly would mean reading that gutter, which belongs to the
    /// split view and is not available here — so the offset was left visible rather than
    /// covered with a constant fitted to one device. A toolbar puts the button in the row the
    /// other controls are already in, which is where it belongs and needs no matching.
    ///
    /// Moving the button to the *detail* column's toolbar broke the app outright: with nothing
    /// but a transparent fill left here, that fill had no intrinsic size, so it won the width
    /// negotiation and swallowed the window. Hence the explicit `width:` — it is what keeps
    /// this column a rail instead of a hole, and it must stay.
    private var collapsedRail: some View {
        CalendarListView(
            mode: .active,
            selectedCalendarID: selectedCalendarID,
            onSelectCalendar: { id in
                // Routed through `switchCalendar` for the same reason the expanded list is: the
                // store's guard gets a say before the calendar being left is abandoned, and a
                // tap from the rail is a tap from the list.
                Task { await navigation.switchCalendar(to: id) }
            },
            onCalendarRemoved: { id in closeIfSelected(id) },
            undoWindowDuration: PCAppSession.makeUndoWindowDuration(),
            layout: .compact
        )
        /// Horizontal only. This is the modifier that makes the cards fill the column.
        ///
        /// Two earlier attempts failed and neither was the frame. `.contentMargins(.horizontal,
        /// 0, for: .scrollContent)` sets the scroll *container's* margins, which is a different
        /// inset from the one in play: the gap came from the scroll view honouring the safe area
        /// around its content, and that has to be turned off directly.
        ///
        /// Vertical is left alone deliberately — that is what keeps the first entries clear of
        /// the toolbar overlaying this column.
        .ignoresSafeArea(.container, edges: .horizontal)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // No `withAnimation`, and it is not an oversight — the column snaps rather
                    // than sliding, and that is settled rather than unfinished. See
                    // `collapsedColumnWidth` for why neither transaction-based approach can reach
                    // a split view's own layout pass.
                    navigation.columnsCollapsed = false
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityIdentifier("content-column-expand")
            }
        }
    }

    /// So rotating back to portrait restores the full list on its own: the gate above goes false
    /// with no observer having to write anything back.
    var body: some View {
        if navigation.columnsCollapsedAreEffective {
            collapsedRail
                /// `backgroundMain`, the same colour every other surface uses.
                ///
                /// Was a hard-coded blue while the rail was scaffolding; it is now themed, so the
                /// collapsed column matches the detail column beside it rather than reading as a
                /// foreign stripe down the leading edge.
                .background(vibe.color(for: .backgroundMain))
                /// Reaching the screen edge is a separate concern from the content's own insets,
                /// so it lives here rather than on the list: the cards stay clear of the notch
                /// while the fill runs to the edge.
                ///
                /// `.top` and `.bottom` as well as `.leading`, because leaving them out is what
                /// produced a rail that was coloured in the middle and cream above and below it —
                /// the split view's toolbar and the home indicator strip are both safe area, and
                /// a fill that respects them reads as a floating band rather than a column that
                /// runs the height of the screen.
                .background(vibe.color(for: .backgroundMain).ignoresSafeArea(edges: [.leading, .top, .bottom]))
        } else {
            content
                .toolbar {
                    /// Only where collapsing is possible at all.
                    ///
                    /// Gated on the same derived value that decides whether the rail draws, so
                    /// the control cannot appear somewhere it would do nothing — an iPad, or a
                    /// phone in portrait, has the full width for three columns and no reason to
                    /// give any of it up. Gating the two independently is what let this show up
                    /// on shapes it cannot help.
                    if navigation.isPhoneLandscape {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                navigation.columnsCollapsed = true
                            } label: {
                                Image(systemName: "chevron.left.2")
                            }
                            .accessibilityIdentifier("content-column-collapse")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.selectedSidebarCategory {
        case .calendarList, .none:
            CalendarListView(
                mode: .active,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    // Routed through `switchCalendar` so the store's guard gets a say: an
                    // unsaved write must not be abandoned by switching away from it. The
                    // reset-to-root behaviour lives there too — selecting from the list always
                    // resets the detail column to its root, unconditionally, including when
                    // `id` is the calendar already on screen. A tap is a request to show that
                    // calendar, and the honest response to "show me this" is the calendar
                    // itself, never a stale screen pushed on top of it. Deciding
                    // conditionally would make tapping a row do nothing when that row is the
                    // current one, so re-selecting became indistinguishable from a dead
                    // control.
                    Task { await navigation.switchCalendar(to: id) }
                },
                onCalendarRemoved: { id in closeIfSelected(id) },
                undoWindowDuration: PCAppSession.makeUndoWindowDuration()
            )
        case .archived:
            CalendarListView(
                mode: .archived,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    Task { await navigation.switchCalendar(to: id) }
                },
                // Wired here as well as in the active list, and it is not redundant: deleting
                // for good is only reachable from this list, and that is the case where the
                // detail has the least to say — the row is gone from storage, so the detail
                // would fetch, find nothing and render nothing at all.
                onCalendarRemoved: { id in closeIfSelected(id) },
                undoWindowDuration: PCAppSession.makeUndoWindowDuration()
            )
        case .settings:
            SettingsView()
        }
    }
}
