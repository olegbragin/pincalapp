//
//  PCEventTimePicker.swift
//  DSKit
//
//  Created by Oleg Bragin on 15.10.2026.
//

import SwiftUI

/// A row that opens the hour and minute wheels and commits when the **minutes** move.
///
/// ## Why two `Picker`s and not a `DatePicker`
///
/// A `DatePicker` presents both wheels as one control, so its `selection` setter cannot say
/// which one moved. That mattered: binding it to the store wrote the time the instant the
/// *hour* moved, and since applying a time clears the selection, the events were gone before
/// the user reached the minutes — an hour was set, at :00, on a selection they had not
/// finished describing.
///
/// Split into one `Picker` per component, each wheel is its own binding and the distinction
/// is expressible: the **hour** only updates the draft, and the **minute** is the commit.
/// Turning the hour to 10 then the minutes to 30 is one write of 10:30; stopping at the hour
/// writes nothing, which is the point — a time of 10:00 chosen deliberately, and a time of
/// 10:00 chosen by accident on the way to 10:30, are indistinguishable in the state and must
/// not be distinguishable in the result either.
///
/// Nothing in SwiftUI reports "the wheel stopped", so Done is still there: it commits the
/// draft as it stands for a user who set only the hour, and Cancel throws the draft away.
public struct PCEventTimePicker: View {
    private let displayedTime: Date
    private let isEnabled: Bool
    private let accessibilityName: String
    private let title: String
    private let cancelTitle: String
    private let doneTitle: String
    private let onCommit: (Date) -> Void

    /// `nil` means the popover is closed; the value is the draft while it is open.
    @State private var draft: Date?

    /// - Parameters:
    ///   - title: The popover's title. Also names the wheels, whose own labels are hidden.
    ///   - cancelTitle: The discard button's name — and its accessibility label, since the
    ///     button is an icon.
    ///   - doneTitle: The commit button's name, likewise.
    ///   - accessibilityName: What VoiceOver calls the row itself. Separate from `title`
    ///     because the row shows no text at all — it is a time and a glyph — while the
    ///     popover it opens is titled.
    ///
    /// The three strings are parameters rather than literals because DSKit does not choose its
    /// own words: `DSKitTests` fails the package on a string literal in a user-facing position,
    /// and on any reference to localization at all. A control that owns its wording cannot be
    /// translated by the caller, so the caller brings it.
    public init(
        displayedTime: Date,
        isEnabled: Bool,
        title: String,
        cancelTitle: String,
        doneTitle: String,
        accessibilityName: String,
        onCommit: @escaping (Date) -> Void
    ) {
        self.displayedTime = displayedTime
        self.isEnabled = isEnabled
        self.title = title
        self.cancelTitle = cancelTitle
        self.doneTitle = doneTitle
        self.accessibilityName = accessibilityName
        self.onCommit = onCommit
    }

    public var body: some View {
        Button {
            draft = displayedTime
        } label: {
            // No "Event time" label beside the value.
            //
            // The row sits alone in its group with nothing to identify it, so the word was
            // doing work — but it named what the thing is while the popover's own title
            // already says what choosing one does, and on the pad it pushed the time off the
            // centre of the row it was supposed to be labelling. The value carries the row
            // now; the glyph is what says it opens something.
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(displayedTime, style: .time)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // The label is gone from the screen, so it has to survive here: with nothing but a
        // time and a glyph, VoiceOver would otherwise read out "10:30, chevron up chevron
        // down, button" and stop there.
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityValue(Text(displayedTime, style: .time))
        .accessibilityIdentifier("batch-events-time-picker")
        .popover(isPresented: Binding(
            get: { draft != nil },
            set: {
                if !$0 {
                    draft = nil
                }
            }
        )) {
            wheel
        }
    }

    private var wheel: some View {
        // A `NavigationStack` around the wheels, and that is load-bearing rather than
        // ceremony: a `toolbar` has nothing to render into on a bare view, so the Cancel/Done
        // items were simply absent — no bar, no buttons, and the only way out of the
        // presentation was to swipe it away, which threw the draft out with it.
        NavigationStack {
            HStack(spacing: 0) {
                hourWheel
                minuteWheel
            }
            .frame(maxHeight: .infinity)
            // Named, because the wheels are an anonymous pair otherwise: the bar has two
            // buttons on it and nothing in the middle to say what they are decisions about.
            .navigationTitle(Text(title))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // Icons, with the words kept for VoiceOver.
                //
                // A bar two buttons wide on a 280pt sheet has room for glyphs and not for
                // "Cancel" and "Done" beside them; the titles are what a screen reader
                // announces, and a glyph with no label announces as "button". `role:` still
                // carries the meaning for the system — the escape gesture discards a draft,
                // which is what `.cancel` means.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        draft = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(cancelTitle))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let draft {
                            onCommit(draft)
                        }
                        draft = nil
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel(Text(doneTitle))
                }
            }
            // A fixed height, not a fraction of the screen.
            //
            // Two wheels are about 200pt and nothing else is in here, so anything
            // proportional opened a mostly-empty sheet. `.presentationDetents` does nothing on
            // a popover presented on iPad, so this is a phone-only guarantee: on a pad this
            // is still a popover anchored to the row.
            .presentationDetents([.height(280)])
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var hourWheel: some View {
        // A literal, not one of the generated `.selectEventTime` keys: those symbols are
        // written per package from that package's own catalog, so a DSKit file cannot name
        // one. The label is never shown — `labelsHidden` — it only names the control, and
        // "Select time" is what the popover's own title says anyway.
        Picker(
            title,
            selection: hourBinding
        ) {
            ForEach(0..<24, id: \.self) { hour in
                // `verbatim`: these are digits, not words, and `Text("\(hour)")` would make
                // SwiftUI extract a format specifier per value into the catalog.
                Text(verbatim: String(format: "%02d", hour))
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .accessibilityIdentifier("batch-events-hour-wheel")
    }

    private var minuteWheel: some View {
        Picker(
            title,
            selection: minuteBinding
        ) {
            ForEach(0..<60, id: \.self) { minute in
                Text(verbatim: String(format: "%02d", minute))
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .accessibilityIdentifier("batch-events-minute-wheel")
    }

    /// Draft-only. Turning the hour is a choice in progress, not a decision.
    private var hourBinding: Binding<Int> {
        Binding(
            get: { component(.hour) },
            set: { draft = composed(hour: $0, minute: component(.minute)) }
        )
    }

    /// The commit, and the end of the presentation.
    ///
    /// The minute is the last thing anyone touches before they are done, so moving it both
    /// applies the time and closes the sheet — the same result as setting hours and minutes
    /// and pressing Done, reached without the extra tap. Closing *here* rather than only
    /// clearing the draft is what makes that true: `draft` is also what holds the popover up,
    /// so nil-ing it is the dismissal.
    private var minuteBinding: Binding<Int> {
        Binding(
            get: { component(.minute) },
            set: {
                let committed = composed(hour: component(.hour), minute: $0)
                onCommit(committed)
                draft = nil
            }
        )
    }

    private var working: Date {
        draft ?? displayedTime
    }

    private func component(_ key: Calendar.Component) -> Int {
        Calendar.current.component(key, from: working)
    }

    /// The two components put back together on `working`'s own day, so committing a time never
    /// moves an event's date — the day is the event's, and only the clock belongs to the picker.
    private func composed(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: working)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? working
    }
}
