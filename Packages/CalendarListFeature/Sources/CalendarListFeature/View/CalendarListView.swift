
import SwiftUI
import CoreDomain
import DSKit

public struct CalendarListView: View {
    @Environment(\.calendarManaging) private var managing
    @Environment(\.pcVibe) private var vibe
    @State private var viewModel: CalendarListViewModel?
    @State private var isAddSheetPresented = false

    /// One stack for every toast this screen raises.
    ///
    /// Shared on purpose. These three can be true at the same time — a calendar archived, a
    /// load that failed, a write that failed — and with a stack each they queue with the
    /// newest nearest the edge, instead of three overlays landing on top of one another and
    /// burying the Retry the user is actually there for.
    @State private var toasts = PCToastStack()
    public var selectedCalendarID: Int64?
    public var onSelectCalendar: (Int64) -> Void = { _ in }

    /// A calendar left the active set — archived, or deleted for good.
    ///
    /// The list is the only screen that watches calendars come and go, so it is the only place
    /// that can say this happened. Whoever put a calendar on screen needs to hear it: a calendar
    /// that has been archived is not one to keep showing. Defaults to doing nothing so a list
    /// embedded anywhere without a detail column behind it needs no wiring.
    public var onCalendarRemoved: (Int64) -> Void = { _ in }

    /// Told when a load fails, with the error that came back. Handed to the view model in `.task`;
    /// see `CalendarListViewModel.onLoadFailed`.
    ///
    /// Reporting rather than recording from inside this package: the reporter lives in
    /// `CorePersistence`, which this package does not depend on and should not. What this package
    /// knows is *that* a load failed, and the owner of the data — the app target, which imports
    /// everything — decides what to do with that. Optional, and `nil` by default, so a caller that
    /// does not care is unaffected.
    public var onLoadFailed: ((any Error) -> Void)?

    /// Told when a write fails, with the failure that has to be retried. Handed to the view model
    /// in `.task`; see `CalendarListViewModel.onWriteFailed`.
    ///
    /// Separate from `onLoadFailed` because the two are not the same event: a write failure carries
    /// its own retry payload and is offered to the user, whereas a load failure keeps the last
    /// known calendars and only says they may be stale. Collapsing them would hand the owner one
    /// shape and force it to re-derive which kind it was looking at.
    public var onWriteFailed: ((PCCalendarListWriteFailure) -> Void)?

    let mode: CalendarListMode

    /// How long the undo toast stays up. See `CalendarListViewModel.undoWindowDuration`.
    let undoWindowDuration: TimeInterval

    /// Which card to draw. `.compact` is for the collapsed landscape rail.
    let layout: PCCardLayout

    public init(
        mode: CalendarListMode = .active,
        selectedCalendarID: Int64? = nil,
        onSelectCalendar: @escaping (Int64) -> Void = { _ in },
        onCalendarRemoved: @escaping (Int64) -> Void = { _ in },
        onLoadFailed: ((any Error) -> Void)? = nil,
        onWriteFailed: ((PCCalendarListWriteFailure) -> Void)? = nil,
        undoWindowDuration: TimeInterval = 5,
        layout: PCCardLayout = .full
    ) {
        self.mode = mode
        self.selectedCalendarID = selectedCalendarID
        self.onSelectCalendar = onSelectCalendar
        self.onCalendarRemoved = onCalendarRemoved
        self.onLoadFailed = onLoadFailed
        self.onWriteFailed = onWriteFailed
        self.undoWindowDuration = undoWindowDuration
        self.layout = layout
    }

    /// Nothing in compact: the title does not fit 66pt, and the column is a rail.
    @ViewBuilder
    private var title: some View {
        if layout != .compact {
            Text(mode == .active ? .myCalendars : .archived)
                .font(.headline)
        }
    }

    /// - Parameter viewModel: the unwrapped model, passed in rather than read from `self`:
    ///   `self.viewModel` is still optional out here, and this is only ever built from
    ///   `content(for:)`, which is where it is known to be non-nil.
    @ViewBuilder
    private func addButton(for viewModel: CalendarListViewModel) -> some View {
        if !viewModel.isAnyCardEditing, mode == .active, layout != .compact {
            Button {
                viewModel.addItem()
                isAddSheetPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
                    .frame(width: 56, height: 56)
            }
            .pcGlass(cornerRadius: 28, tint: .black.opacity(0.22))
            .clipShape(Circle())
            /// The route to "there are no calendars, so make one". It is a symbol with no
            /// text, so without an identifier there is nothing stable to find it by.
            .accessibilityIdentifier("calendar-list-add-button")
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .transition(.scale.combined(with: .opacity))
        }
    }

    public var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                PCProgressView(label: String(localized: .loading))
            }
        }
        .task {
            if viewModel == nil {
                guard let managing else { return }
                let model = CalendarListViewModel(mode: mode, managing: managing, undoWindowDuration: undoWindowDuration)
                // Assigned here rather than folded into `init`: the callbacks close over this
                // view's parameters, and the view model is only ever built once. A list that
                // swapped modes would keep the first model's callbacks — which is why
                // `RootContentView` tears the view down between modes instead of reconfiguring it.
                model.store.onCalendarRemoved = onCalendarRemoved
                model.store.onLoadFailed = onLoadFailed
                model.store.onWriteFailed = onWriteFailed
                viewModel = model
            }
            // `fetch` dispatches `.loadStarted` and then awaits the load, rethrowing. There is
            // no caller left here to branch on that: the failure is already recorded in
            // `loadFailure` for the toast and raised to `onLoadFailed` for the app target.
            try? await viewModel?.fetch()
        }
    }

    @ViewBuilder
    private func content(for model: CalendarListViewModel) -> some View {
        // The `@Sendable` refresh closure below must capture the immutable parameter,
        // not this `@Bindable` shadow, which is a `var` the compiler rightly refuses to
        // let escape into concurrent code.
        @Bindable var viewModel = model
        VStack(spacing: 0) {
            if viewModel.isLoading, viewModel.calendars.isEmpty {
                Spacer()
                PCProgressView(label: String(localized: .loading))
                Spacer()
            } else {
                CalendarListContent(
                    calendars: viewModel.calendars,
                    displayMode: viewModel.displayMode,
                    isArchived: mode == .archived,
                    cardViewModelFactory: { viewModel.cardViewModel(for: $0) },
                    onCalendarDelete: { viewModel.archiveCalendarInList($0) },
                    onCalendarRestore: { viewModel.restoreCalendarInList($0) },
                    onCalendarPermanentDelete: { viewModel.permanentlyDeleteCalendar($0) },
                    // `fetch` records the failure and raises `onLoadFailed` from its own catch,
                    // then rethrows. The rethrow is what lets `safeRefreshable` take its spinner
                    // down rather than strand it.
                    //
                    // No `onRefreshFailed` is passed, and that is deliberate rather than an
                    // omission: the error is already reported by the time it arrives here, and
                    // `PCSafeRefreshableModifier` optional-chains the callback and puts the
                    // spinner away unconditionally either way — so a closure that did nothing
                    // would be indistinguishable from passing none. This used to be where the
                    // reporting happened, which is why it needed `MainActor.assumeIsolated` to
                    // reach a main-actor property from a `@Sendable` closure; the report moved
                    // into the store and the hop went with it.
                    onRefresh: { try await model.fetch() },
                    selectedCalendarID: selectedCalendarID,
                    onSelectCalendar: onSelectCalendar,
                    cardLayout: layout
                )
            }

            Text(viewModel.appVersion)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        // The themed background rather than a system grouped one, so this column matches the
        // detail column beside it. `systemGroupedBackground` is a near-neutral system grey, which
        // put two visibly different backgrounds either side of a single divider — and it ignored
        // the vibe entirely, so a theme could not have reached it. `.backgroundMain` is
        // `#F4F0EA` in light and carries its own dark variant, which is also what the launch
        // screen paints.
        .background(vibe.color(for: .backgroundMain))
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottomTrailing) {
            addButton(for: viewModel)
        }
        .pcNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                title
            }
            /// Hidden when compact.
            ///
            /// The collapsed rail forces a single column, so this control would claim to offer
            /// a choice that does not exist — and at 66pt it cannot render a `Label` with both
            /// text and an icon anyway. `.hidden` rather than removed from the `ToolbarItem` so
            /// the placement stays reserved and does not shift the expand button on toggle.
            if layout != .compact {
                ToolbarItem(placement: .pcTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.toggleDisplayMode()
                        }
                    } label: {
                        Label(viewModel.displayMode.toggled.label, systemImage: viewModel.displayMode.toggled.icon)
                    }
                }
            }
        }
        .onChange(of: viewModel.addEditCalendarViewModel.calendar) {
            if $0 != $1, let calendar = $1 {
                viewModel.addCalendar(with: calendar.name)
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddEditCalendarView(viewModel: viewModel.addEditCalendarViewModel)
        }
        .pcToast(
            isPresented: viewModel.archiveToastPresentedBinding,
            stack: toasts,
            position: .bottom,
            message: viewModel.archiveToastMessage,
            actionTitle: "Undo",
            action: { viewModel.undoArchive() },
            backgroundColor: .black.opacity(0.85),
            progress: viewModel.archiveToastProgress,
            // Named, so a test presses *Undo* rather than tapping the toast body and hoping
            // it landed on the right third of it.
            identifier: "archive-undo-toast",
            actionIdentifier: "archive-undo-toast-button"
        )
        /// A load that failed, offered with a retry.
        ///
        /// The same reasoning as `SingleCalendarView`'s failed-save toast, and for the same
        /// reason: **no progress bar, so it does not fade unattended.** An error that times out
        /// on its own is an error the user walks away from without knowing it happened, which is
        /// the state this whole change exists to end. It clears on the next successful load
        /// (`fetch` does that), not on a timer.
        ///
        /// The list stays visible underneath rather than being replaced — `fetch` keeps the last
        /// known calendars — so the user sees stale data clearly marked as possibly-stale rather
        /// than an empty screen that reads as data loss.
        .pcToast(
            isPresented: model.loadFailureBinding,
            stack: toasts,
            position: .bottom,
            message: "Couldn't load your calendars",
            actionTitle: "Retry",
            action: {
                // A retry is a plain re-read. Its outcome is state: `loadFailure` clears only
                // if this retry landed, and `onLoadFailed` has already been told either way.
                Task { try? await model.fetch() }
            },
            backgroundColor: .black.opacity(0.85),
            /// No progress: this toast has no deadline.
            ///
            /// The bar is the archive window's countdown — it shows how long Undo remains. This
            /// one does not expire, so a bar would imply a timer that does not exist. Omitting
            /// `progress` is what draws no bar at all; the old `progress: 0` drew a full-width
            /// empty track, which said the same thing the code was arguing against.
            identifier: "calendar-list-load-failed-toast",
            actionIdentifier: "calendar-list-load-failed-retry"
        )
        /// A write that did not land, offered with a retry of *that* write.
        ///
        /// Two distinct toasts, and deliberately not one with a shared message: a failed read is
        /// retried by re-reading, a failed write by re-doing the operation it was. Collapsing them
        /// would mean a "Retry" that silently did something other than what the user just watched
        /// fail.
        ///
        /// No progress bar and no timeout, for the same reason as the load toast: an error that
        /// fades on its own is an error the user never learns about. It clears when the retry
        /// succeeds or when a different write fails.
        ///
        /// The permanent delete's message says it plainly, because its retry is the only way back
        /// and the user should not have to infer that from an icon.
        .pcToast(
            isPresented: model.writeFailureBinding,
            stack: toasts,
            position: .bottom,
            message: writeFailureMessage(for: model),
            actionTitle: "Retry",
            action: { model.retryWriteFailure() },
            backgroundColor: .black.opacity(0.85),
            /// No bar, for the reason above the load toast: nothing here expires, and a bar is
            /// a promise that something is about to end.
            identifier: "calendar-list-write-failed-toast",
            actionIdentifier: "calendar-list-write-failed-retry"
        )
    }

    /// The words for a failed write.
    ///
    /// Built here, in the view, rather than stored on the failure — the same split
    /// `RootView`'s deep-link alert uses: the model says *what* failed, this decides what to say
    /// about it. The permanent delete is called out separately because its retry is destructive
    /// and irreversible, and a generic "Retry" on a delete is a trap.
    private func writeFailureMessage(for model: CalendarListViewModel) -> String {
        guard let failure = model.writeFailure else { return "" }
        let name = failure.calendarName
        switch failure.operation {
        case .create:
            return "Couldn't create the calendar"
        case .rename:
            return "Couldn't rename \(name ?? "the calendar")"
        case .archive:
            return "Couldn't archive \(name ?? "the calendar")"
        case .restore:
            return "Couldn't restore \(name ?? "the calendar")"
        case .permanentlyDelete:
            return "Couldn't delete \(name ?? "the calendar"). This can't be undone."
        }
    }
}
