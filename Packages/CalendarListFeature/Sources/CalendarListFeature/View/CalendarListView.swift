
import SwiftUI
import CoreDomain
import DSKit

public struct CalendarListView: View {
    @Environment(\.calendarManaging) private var managing
    @Environment(\.pcVibe) private var vibe
    @State private var viewModel: CalendarListViewModel?
    @State private var isAddSheetPresented = false
    public var selectedCalendarID: Int64?
    public var onSelectCalendar: (Int64) -> Void = { _ in }

    /// A calendar left the active set — archived, or deleted for good.
    ///
    /// The list is the only screen that watches calendars come and go, so it is the only place
    /// that can say this happened. Whoever put a calendar on screen needs to hear it: a calendar
    /// that has been archived is not one to keep showing. Defaults to doing nothing so a list
    /// embedded anywhere without a detail column behind it needs no wiring.
    public var onCalendarRemoved: (Int64) -> Void = { _ in }

    /// Told when a load fails, with the error that came back.
    ///
    /// Reporting rather than recording from inside this package: the reporter lives in
    /// `CorePersistence`, which this package does not depend on and should not. What this package
    /// knows is *that* a load failed, and the owner of the data — the app target, which imports
    /// everything — decides what to do with that. Optional, and `nil` by default, so a caller that
    /// does not care is unaffected.
    public var onLoadFailed: ((any Error) -> Void)?

    /// Told when a write fails, with the failure that has to be retried.
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
                // Assigned here rather than folded into `init`: the callback closes over this
                // view's parameter, and the view model is only ever built once. A list that
                // swapped modes would keep the first model's callback — which is why `RootContentView`
                // tears the view down between modes instead of reconfiguring it.
                model.onCalendarRemoved = onCalendarRemoved
                viewModel = model
            }
            // The view model now records the failure in `loadFailure` and keeps the previous
            // list, so a failed load no longer empties the screen — that is handled, and
            // the catch is only discarding the rethrow.
            //
            // Still `try?`, deliberately and **not** finished business: nothing reads
            // `loadFailure` yet, so the user is still not told. What is left is the
            // presentation, which is this package's decision about its own words and the
            // app's about how they are offered.
            do {
                try await viewModel?.fetch()
            } catch {
                // `fetch` already recorded the failure and kept the last known calendars, so
                // this is reporting, not recovery. The `try?` this replaces discarded the very
                // thing the owner most wants to hear about.
                onLoadFailed?(error)
            }
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
                    // `fetch` records the failure in `loadFailure` and rethrows; the rethrow is
                    // what lets `safeRefreshable`'s spinner be taken down rather than stranded.
                    onRefresh: { try await model.fetch() },
                    onRefreshFailed: { error in
                        // Reported upward rather than swallowed. `CalendarListContent` is a
                        // presentational list with no vocabulary of its own, so it hands the error
                        // to whoever owns the model and can say something about it.
                        //
                        // Hopped back to the main actor because that closure is `@Sendable` and
                        // this property is main-actor-isolated — it belongs to a `View`, and the
                        // compiler will not let a Sendable closure read it directly. The refresh
                        // that produced this error always runs on the main actor anyway, so
                        // `assumeIsolated` is true by construction; the alternative, a `Task`, would
                        // make the report land a runloop later than the failure for no gain.
                        MainActor.assumeIsolated { onLoadFailed?(error) }
                    },
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
        /// Reports write failures upward.
        ///
        /// Observed rather than caught, because a write failure does not throw: `recordWriteFailure`
        /// stores it and returns, so the failure *is* the state. Reading it here rather than at each
        /// call site is what keeps this to one place — there are five write entry points, and a
        /// `do/catch` in each would be five chances to forget one.
        ///
        /// Fires on the `nil -> failure` edge only. Re-assigning the same failure — which a retry
        /// does when it fails the same way — would otherwise report the same failure twice.
        .onChange(of: viewModel.writeFailure) { _, failure in
            guard let failure else { return }
            onWriteFailed?(failure)
        }
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
                            viewModel.displayMode = viewModel.displayMode.toggled
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
            isPresented: $viewModel.isArchiveToastPresented,
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
            isPresented: loadFailureBinding(for: model),
            position: .bottom,
            message: "Couldn't load your calendars",
            actionTitle: "Retry",
            action: {
                Task {
                    do {
                        try await model.fetch()
                    } catch {
                        onLoadFailed?(error)
                    }
                }
            },
            backgroundColor: .black.opacity(0.85),
            /// No progress: this toast has no deadline.
            ///
            /// The bar is the archive window's countdown — it shows how long Undo remains. This
            /// one does not expire, so a bar would imply a timer that does not exist.
            progress: 0,
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
            isPresented: writeFailureBinding(for: model),
            position: .bottom,
            message: writeFailureMessage(for: model),
            actionTitle: "Retry",
            action: { model.retryWriteFailure() },
            backgroundColor: .black.opacity(0.85),
            progress: 0,
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

    /// `loadFailure` as something the toast can bind to.
    ///
    /// `pcToast` takes a `Binding<Bool>` and the model stores a `Bool` that it owns; this is the
    /// adapter, and `set` is empty because nothing here *clears* the failure — `fetch` does, on
    /// success. A binding that could write it would let a dismissed toast look like a resolved
    /// one.
    private func loadFailureBinding(for model: CalendarListViewModel) -> Binding<Bool> {
        Binding(get: { model.loadFailure }, set: { _ in })
    }

    /// `writeFailure`'s presence as something the toast can bind to.
    ///
    /// Same one-way shape as the load binding, and for a sharper reason: dismissing this toast
    /// must not clear the failure, because the write did not happen and the only thing that can
    /// clear it is a write succeeding. A dismissible-looking failure that a swipe could remove
    /// would put the app back to swallowing errors.
    private func writeFailureBinding(for model: CalendarListViewModel) -> Binding<Bool> {
        Binding(get: { model.writeFailure != nil }, set: { _ in })
    }
}
