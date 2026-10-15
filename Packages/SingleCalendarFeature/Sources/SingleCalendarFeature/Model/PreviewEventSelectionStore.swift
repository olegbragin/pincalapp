//
//  PreviewEventSelectionStore.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 15.10.2026.
//

#if DEBUG
    import Foundation
    import CoreDomain
    import DSKit

    /// A store for `#Preview`, standing in for the one the app root injects.
    ///
    /// The batch editor reads `PCEventSelectionManager` out of the environment and traps without
    /// it — `EnvironmentValues.subscript.getter` calls `fatalError` on a missing observable — so
    /// every preview of this feature crashed at the first frame rather than showing a screen. That
    /// is a bad way to find out a layout changed: the only way to see the editor was to build and
    /// run it, which is exactly what a preview is for.
    ///
    /// The state is the one the editor opens into, not an empty one: a staged batch over three
    /// days with a name and a colour, because the interesting questions about this screen — do the
    /// rows fit, does the panel fill its half, does the time read correctly beside them — are all
    /// questions about a screen with *something in it*. A preview of three empty halves would have
    /// answered none of them.
    ///
    /// Built as `initialState` rather than by sending actions, and that is not a shortcut. Two of
    /// the actions a real opening makes are asynchronous in the ways that matter here: `setBatchName`
    /// is debounced, so a name sent from a fixture is still blank when the preview snapshots, and
    /// the write chain is scheduler-driven, so rows appear a frame or two late. Both were observed
    /// in the first version of this file, which rendered a correct-looking panel with no name and
    /// no events in it — a preview that quietly proves nothing.
    enum PreviewEventSelectionStore {
        /// A manager already inside the batch editor, with a staged batch over three days.
        @MainActor
        static func make() -> PCEventSelectionManager {
            let provider = PCCalendarDataProvider()
            var state = PCEventSelectionState(dataProvider: provider)
            state.calendarID = 1
            state.stage = .batchEditor

            // Days 1..3 of the current month — the same days the UI fixtures use — built by the
            // reducer's own two steps so the assembly carries `pendingID`s it would really have.
            var assembly = PCEventBatchAssembleUnitOfWork.new(
                anchor: day(1, provider: provider),
                colorName: PCColorOption.firstAvailable.colorName,
                using: provider
            )
            for dayOfMonth in 2...3 {
                assembly = assembly.toggling(day: day(dayOfMonth, provider: provider), using: provider)
            }
            state.day = day(1, provider: provider)
            state.assembly = assembly
            state.scrollAnchor = state.day
            state.batches = [assembly.resolved()!]
            state.dayEventColors = state.derivedDayEventColors

            return PCEventSelectionManager(
                initialState: state,
                persistence: PreviewCalendarPersisting(),
                daySelectionManager: PCCalendarDaySelectionManager()
            )
        }

        /// Midday, so the day is named unambiguously whatever zone the preview renders in.
        @MainActor
        private static func day(_ dayOfMonth: Int, provider: PCCalendarDataProvider) -> Date {
            var components = provider.dateComponents(forDate: Date())
            components.day = dayOfMonth
            components.hour = 12
            return Calendar.current.date(from: components) ?? Date()
        }

        /// The main calendar's own model, over a store at the calendar's stage.
        ///
        /// Kept as a separate entry point from `make()` because the two screens need *different*
        /// stores, not because a calendar needs its own: `SingleCalendarView` decides what to draw
        /// from `store.state.stage`, and a store parked in `.batchEditor` for the editor's preview
        /// renders as a blank screen here. This is the same batch, committed to `batches` and
        /// sitting at `.calendar`, which is the state a synced calendar is actually in.
        @MainActor
        static func makeCalendarModel() -> SingleCalendarModel {
            let calendar = previewCalendar()
            let store = makeCalendarStore()
            let model = SingleCalendarModel(
                calendarid: 1,
                managing: PreviewCalendarManaging(),
                persistence: PreviewCalendarPersisting(
                    calendar: calendar,
                    batches: store.state.batches
                ),
                store: store
            )

            // Pre-loaded, because `fetch()` is asynchronous and a preview does not wait for it.
            //
            // The calendar screen starts in `.empty` and reaches `.content` only inside the
            // `.task` that calls `fetch`, so a snapshot taken before that task's first await
            // catches `EmptyView` — a blank page that reads as a layout bug and is a timing
            // accident. `state` and the markers are the two things the screen cannot draw
            // without, and both are set here exactly as `fetch` would set them from the same port
            // data; the title is not, because `label` has no public setter and the `.task` owns
            // it. When the task does run it recomputes all three to the same values.
            model.state = .content
            model.projectMarkers()
            return model
        }

        /// The batch the calendar preview marks its days with — the same three days, committed.
        @MainActor
        private static func previewBatch(_ provider: PCCalendarDataProvider) -> CalendarEventBatch {
            var assembly = PCEventBatchAssembleUnitOfWork.new(
                anchor: day(1, provider: provider),
                colorName: PCColorOption.firstAvailable.colorName,
                using: provider
            )
            for dayOfMonth in 2...3 {
                assembly = assembly.toggling(day: day(dayOfMonth, provider: provider), using: provider)
            }
            return assembly.resolved()!
        }

        @MainActor
        private static func previewCalendar() -> PinCalendar {
            PinCalendar(
                id: 1,
                name: "New calendar",
                year: Calendar.current.component(.year, from: Date()),
                numberOfColumns: 3
            )
        }

        /// The store the **main calendar** screen renders from.
        ///
        /// A second store on purpose, and the difference from `make()` is the whole point: the
        /// calendar view reads `store.state.stage` to decide what to draw, and a store sitting in
        /// `.batchEditor` — which is what the editor needs — renders as nothing at all. This one
        /// is at `.calendar` with the batch already *committed* to `batches`, which is where a
        /// synced calendar's batch lives, so the days come back marked.
        @MainActor
        static func makeCalendarStore() -> PCEventSelectionManager {
            let provider = PCCalendarDataProvider()
            var state = PCEventSelectionState(dataProvider: provider)
            state.calendarID = 1
            state.day = day(1, provider: provider)
            state.batches = [previewBatch(provider)]
            state.dayEventColors = state.derivedDayEventColors

            return PCEventSelectionManager(
                initialState: state,
                persistence: PreviewCalendarPersisting(),
                daySelectionManager: PCCalendarDaySelectionManager()
            )
        }
    }

    /// The port behind `PreviewEventSelectionStore`.
    ///
    /// Writes are dropped; reads answer whatever the fixture was given. Routing the previews
    /// through the real port rather than faking the store is the point — the editor's own
    /// write chain, debounce and `failedSave` handling all run exactly as they do in the app.
    /// `Sendable` is satisfied by the value type it is, with no locking needed for the same
    /// reason.
    private struct PreviewCalendarPersisting: CalendarPersisting {
        /// The calendar `SingleCalendarModel.fetch` must find, and the batches it must read.
        ///
        /// Not optional, for the calendar screen. `fetch` treats a `nil` calendar as "this
        /// calendar does not exist" and puts the screen in `.empty`, which is `EmptyView` — the
        /// preview rendered a blank page that looked like a layout bug and was actually a
        /// fixture answering "no". The editor's previews never noticed, because nothing they
        /// show calls `fetch`.
        private let calendar: PinCalendar?
        private let batches: [CalendarEventBatch]

        init(calendar: PinCalendar? = nil, batches: [CalendarEventBatch] = []) {
            self.calendar = calendar
            self.batches = batches
        }

        func calendar(id: Int64) async throws -> PinCalendar? {
            calendar
        }

        func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch] {
            batches
        }

        func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws {}
    }

    /// The calendar-list port behind `PreviewEventSelectionStore.makeCalendarModel()`.
    ///
    /// `changes()` returns a stream that ends immediately and publishes nothing. That is the
    /// honest shape for a preview: the model's subscription loop ends on the stream's end and
    /// the calendar renders whatever it loaded. A feed that stayed open forever would hold a
    /// live task for the lifetime of the canvas, which is what a preview should not do.
    private struct PreviewCalendarManaging: CalendarManaging {
        func changes() async -> AsyncStream<PinCalendarChange> {
            AsyncStream { $0.finish() }
        }

        func loadActive() async throws -> [PinCalendar] {
            []
        }

        func loadArchived() async throws -> [PinCalendar] {
            []
        }

        func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws {}

        func updateCalendar(_ calendar: PinCalendar) async throws {}

        func archiveCalendar(id: Int64) async throws {}

        func restoreCalendar(id: Int64) async throws {}

        func permanentlyDeleteCalendar(id: Int64) async throws {}
    }
#endif
