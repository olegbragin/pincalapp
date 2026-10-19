//
//  SingleCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import SwiftUI
import AppNavigation
import DSKit

public struct SingleCalendarView: View {
    @Environment(RootNavigation.self) var navigation
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(\.pcVibe) private var vibe

    @Bindable public var viewModel: SingleCalendarModel

    /// Local so dismissing the toast does not touch the store: the failure is the store's
    /// to hold until it is retried, and clearing it here would unblock the calendar switch
    /// for a save that still has not landed. The store clears `failedSave` itself when a
    /// write succeeds, and this follows it down.
    @State private var isSaveFailedToastPresented = false

    /// Shared with any other toast this screen raises, for the reason `CalendarListView` has
    /// one: a presenter that made its own stack could still only ever show one.
    @State private var toasts = PCToastStack()

    public init(
        viewModel: SingleCalendarModel
    ) {
        self.viewModel = viewModel
    }

    public var body: some View {
        calendarContent
            .ignoresSafeArea(edges: .bottom)
            // The batch editor, as a sheet over this calendar.
            //
            // Attached here rather than inside the `NavigationStack` so the sheet is not
            // nested in the stack it edits, and wrapped in its own `NavigationStack` because
            // a `ToolbarItem` only renders inside one — without it the editor's Back would be
            // built and never shown, which is the one affordance the editor is not allowed to
            // be without. `SingleCalendarView` itself stays mounted underneath, which is the
            // point: its day markers follow every edit as it is made.
            //
            // Split out as its own view for the type-checker, not for tidiness: with the
            // sheet's `NavigationStack` inline this body stopped type-checking inside the
            // compiler's budget, and the fix that works is to give the heaviest subtree its
            // own `body` rather than to shave expressions off this one.
            .sheet(isPresented: sheetBinding) {
                batchEditorSheet
            }
            .sensoryFeedback(.success, trigger: viewModel.isMultiSelectMode)
            .task(id: viewModel.calendarid) {
                viewModel.installDayTapHandler()
                // A failed fetch leaves the model in whatever state it was in, rather than
                // pretending the calendar is empty — that part is fixed. Reporting it is not, and
                // the catch below preserves the previous quiet behaviour so this step changes
                // nothing a user can observe. Replaced by a surfaced failure in the next step.
                try? await viewModel.fetch()
            }
            .onDisappear {
                viewModel.clearDayTapHandler()
                // Leaving the calendar detail (back to the list, or switching calendars) must
                // exit any active multi-select session so a later reopen starts fresh. Guarded
                // on `isAtRoot` because `onDisappear` also fires when a destination is pushed
                // on top, and a batch edit in progress must not be reset.
                if navigation.isAtRoot {
                    viewModel.cancelMultiSelect()
                }
            }
            .onChange(of: navigation.isAtRoot) { _, isAtRoot in
                if isAtRoot {
                    viewModel.cancelMultiSelect()
                }
            }
            .onChange(of: navigation.presentedSheet) { _, sheet in
                // Take the day-tap handler back from the batch editor.
                //
                // There is exactly one slot (`PCEventSelectionManager.daySelectionManager`), and
                // this view installed into it on appearing while the editor installs into it on
                // the sheet's appearing — the editor wins, because it is later. But the editor
                // *clears* the slot on the sheet's disappearing rather than restoring whoever had
                // it, which is right for the case that motivated it (a handler outliving its
                // screen) and wrong here: the calendar beneath never unmounted, so clearing
                // leaves it with no handler at all and every day tap becomes a no-op after the
                // first time an editor has been opened. Restoring it on dismissal is the handover.
                guard sheet == nil else { return }
                viewModel.installDayTapHandler()
            }
            .onChange(of: store.state.dayEventColors) { _, _ in
                // The editor screens dispatch to the store directly, so the main panel's
                // markers have to follow the store rather than wait to be told. Projecting
                // only on `fetch` was not enough: a staged edit writes nothing, so no cache
                // change fires, and removing the last event of a day left its marker behind.
                viewModel.projectMarkers()
            }
            .onChange(of: store.state.navigationRequest) { _, request in
                // This is where the main calendar leaves the line. The reducer decides that a
                // day tap means "open the batch editor" and says so in `navigationRequest`;
                // carrying that out is the view layer's job, and this is the only place on
                // this screen that can. Without it a day tap staged a batch and nothing
                // happened — which is exactly what the UI suite caught.
                guard let request else { return }
                PCEventSelectionNavigator.fulfil(
                    request,
                    calendarID: viewModel.calendarid,
                    using: navigation,
                    in: store
                )
            }
            /// Shows the failed write. Reporting it is no longer this view's job.
            ///
            /// There used to be an `onSaveFailed` callback here as well, raised from this same
            /// `onChange` so the app target could record the failure. It was a relay for something
            /// `failedSave` already made public and observable: `CalendarDetailView` holds the same
            /// store and can observe it directly, so the callback added a second owner of one event
            /// and nothing else. The reporter still lives in `CorePersistence`, which this package
            /// does not depend on — that constraint is unchanged, it is just now honoured by whoever
            /// actually holds the store.
            ///
            /// Observed rather than caught, because a failed save does not throw — `PCFailedSave` *is*
            /// the state, and it has to stay resident so the retry can replay exactly what failed.
            .onChange(of: store.failedSave) { _, failure in
                // Raised by the store when a write did not land. The toast is the only way the
                // user learns their work is not saved, and Retry is the only way out — which is
                // why there is no timeout here: a failed save must not fade away unattended,
                // unlike the transient toasts that need no answer.
                isSaveFailedToastPresented = failure != nil
            }
            .pcToast(
                isPresented: $isSaveFailedToastPresented,
                stack: toasts,
                position: .bottom,
                message: saveFailureMessage,
                actionTitle: "Retry",
                action: { store.retryFailedSave() },
                backgroundColor: .black.opacity(0.85),
                // A full bar, permanently. Not a countdown — there is no countdown, and that
                // is the point: this toast does not get shorter as it waits, because it is the
                // notice that work was not saved and it has no deadline of its own.
                progress: 1,
                identifier: "save-failed-toast",
                actionIdentifier: "save-failed-toast-button"
            )
    }

    /// The calendar panel, with its destinations.
    ///
    /// Its own `body` rather than an inline subtree. See the note on the sheet above: this
    /// view is where the type-checker was running out of budget, and moving whole subtrees
    /// into their own `body` is what gives it back — shaving expressions does not, because
    /// the cost is the *shape* of the tree, not the length of any one line.
    private var calendarContent: some View {
        ZStack {
            SingleCalendarStateView(state: viewModel.state) {
                AnyView(
                    VStack(spacing: 0) {
                        // `isAtRoot` mirrors the toolbar's own guard below. The picker is
                        // the main calendar's own multi-select session now, and the batch
                        // editor no longer shares this panel's selection state, so nothing
                        // behind a pushed screen can flip it.
                        if navigation.isAtRoot, viewModel.isMultiSelectMode {
                            PCExpandedColorPicker(
                                selectedColor: viewModel.multiSelectColorBinding,
                                optionNames: pcColorOptionNames()
                            )
                            .disabled(viewModel.isColorPickerDisabled)
                        }
                        PCCalendarYearView(
                            viewModel: viewModel.yearModel,
                            selectYearTitle: String(localized: .selectYear),
                            onLongPress: { viewModel.setMultiSelectMode(true) },
                            onYearSelect: { viewModel.switchYear(to: $0) }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: viewModel.yearModel.numberOfColumns) { old, new in
                        if old != new {
                            viewModel.setNumberOfColumns(new)
                        }
                    }
                )
            }
            .padding(6)
            .pcDisableInteractivePopGesture()
            .navigationTitle(viewModel.label)
            .pcNavigationBarTitleDisplayMode(.inline)
            .toolbarBackground(vibe.color(for: .backgroundMain), for: .pcNavigationBar)
            .toolbar { toolbarContent }
            .id(viewModel.calendarid)
            .navigationDestination(for: AppRoute.self) { route in
                // No payload: each screen reads what it needs from the store, so there is
                // no per-destination `case .batchEditor(let source)` preamble here to keep
                // in step with the reducer.
                switch route {
                case .dayBatches:
                    AddEditEventBatchListView(calendarID: viewModel.calendarid)
                case .batchEditor, .calendar, .addCalendar, .sidebar:
                    EmptyView()
                }
            }
        }
    }

    /// The batch editor's sheet.
    ///
    /// Its own `NavigationStack` so the editor's `ToolbarItem`s have somewhere to render. A
    /// sheet's content is not inside the presenting stack, so without one the toolbar is
    /// simply dropped and Back — the editor's only exit — never appears.
    ///
    /// **No `navigationDestination` on this stack any more.** It used to declare `.eventEditor`
    /// here, because the event editor was pushed from inside the sheet and had to be declared on
    /// the stack that would show it; declared on the calendar's own destination instead it
    /// rendered *behind* the sheet, present in the accessibility tree and untappable. With that
    /// screen gone the sheet is a single destination, and the `path` binding is kept only
    /// because `RootNavigation.dismissSheet()` still clears it and `pop()` still prefers it.
    private var batchEditorSheet: some View {
        @Bindable var navigation = navigation
        return NavigationStack(path: $navigation.sheetPath) {
            AddEditEventBatchScreen(calendarID: viewModel.calendarid)
        }
        // A **page** sheet, which covers the window.
        //
        // The default is a *form* sheet on iPad, and it is small: measured at 580x660 on a
        // 13-inch iPad. That is not enough for this editor by a wide margin. The editor's two
        // flexible halves were measured at zero height inside it — the day cells the tests tap
        // left the tree entirely, and with the keyboard up (403pt on iPad) the event list was
        // left with *literally* nothing: its rows stayed in the accessibility tree, outside
        // their own zero-height list, and could not be tapped. A batch editor you cannot add a
        // day to.
        //
        // `.presentationDetents([.large])` is the tempting answer and does nothing: form
        // sheets presented from a split-view column do not take detents, and the sheet stayed
        // 580x660 with it set. `.presentationSizing(.page)` is the one that changes the
        // *style*, and a full-height editor is what the layout was designed against.
        //
        // The cost, stated plainly: on iPad the calendar behind is covered rather than visible
        // behind glass. It is still mounted and its markers still track every edit, but the
        // user cannot watch them happen. That is a real trade against the original intent, and
        // it is worth revisiting with a layout that does not need the whole window.
        .modifier(PCPageSheetSizing())
        // The drag-to-dismiss is off. The Close button is the editor's only exit, and a swipe
        // would be a second one that skips it.
        //
        // This is not about "accidentally" dismissing: leaving is a *store* operation
        // (`.backTapped` merges the staged assembly and deletes the batch's row if it was
        // emptied), and a swipe dismisses the sheet without ever reaching the store. The
        // staged assembly would stay in `state` and the calendar underneath would keep
        // showing markers for edits that were never written — the same failure the explicit
        // Close button exists to prevent, reachable with one finger instead of a tap.
        .interactiveDismissDisabled()
    }

    /// Whether the batch editor's sheet is up, as a `Binding<Bool>`.
    ///
    /// Hand-built rather than `@Bindable` on the environment value, for the reason
    /// `RootNavigation.presentedSheet` is `public private(set)`: the only way out is
    /// `dismissSheet()`, and a synthesised `@Bindable` binding would assign the property
    /// directly and bypass the one method that keeps a dismissal going through the same path
    /// as a presentation.
    ///
    /// A `Bool` rather than `.sheet(item:)` on the route, because `AppRoute` is not
    /// `Identifiable` and making it so would give a *navigation* type an identity for the
    /// sake of a presentation — the route's identity is "where to go", and a sheet's is "is it
    /// showing". `.addCalendar` shares the same slot and has no view for it yet, so the
    /// predicate is spelled for the one that does rather than for the enum.
    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { navigation.presentedSheet == .batchEditor },
            set: { isPresented in
                guard !isPresented else { return }
                navigation.dismissSheet()
            }
        )
    }

    /// User-facing text for a failed save.
    ///
    /// The store's `message` is the raw thrown error, which is not something to put in front
    /// of someone — ObjectBox surfaces internal failures there. So the specifics stay in the
    /// store for diagnosis and the user gets the actionable half: the work is not saved, and
    /// Retry is right there on the toast.
    private var saveFailureMessage: String {
        store.failedSave == nil ? "" : "Couldn't save changes. Retry to keep them."
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if navigation.isAtRoot, !viewModel.isArchived {
            ToolbarItem {
                Button(
                    viewModel.isMultiSelectMode ? .save : .multiselect,
                    systemImage: viewModel.isMultiSelectMode ? "checkmark" : "plus.rectangle.on.rectangle"
                ) {
                    if viewModel.isMultiSelectMode {
                        viewModel.confirmMultiSelect()
                    } else {
                        viewModel.setMultiSelectMode(true)
                    }
                }
            }
        }
    }
}

#Preview {
    // The real view, not a stand-in.
    //
    // This preview used to render a `Text` saying "SingleCalendarView Preview" — which is a
    // preview of nothing and, worse, one that *succeeds*. It looked like the screen had a
    // preview while every change to the calendar, its markers and its toolbar could only be
    // checked by building and running.
    //
    // `SingleCalendarView` takes its model as an argument and reads a root navigation, the
    // vibe and the keyboard state from the environment — the last two trap on a missing
    // observable. The model is built over the *same* store as the editor's preview, so the
    // markers on these days are the batch being edited rather than an unrelated calendar.
    NavigationStack {
        SingleCalendarView(viewModel: PreviewEventSelectionStore.makeCalendarModel())
    }
    .environment(RootNavigation())
    .environment(PreviewEventSelectionStore.make())
    .environment(PCKeyboardState())
}
