//
//  CalendarEventPresentation.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 15.10.2026.
//

import Foundation
import CoreDomain

/// How an event is *stamped* wherever the UI lists it.
///
/// One owner for the format, because two screens already wanted the same string and a second
/// copy is how the batch card and the event list drift into disagreeing about the same event.
/// Both view models expose it (`dateTimeText(for:)`) rather than formatting inline, so a view
/// never has to know the format.
///
/// It is a presentation concern and lives in the feature package, not in `CoreDomain`: the
/// domain must not depend on the user's locale, and the string means nothing without a screen
/// to show it on.
extension CalendarEvent {
    /// Date *and* time — e.g. "Jul 15, 2026 at 3:45 PM", "15 июл. 2026 г. в 15:45".
    ///
    /// A single `Date.FormatStyle` carrying both halves rather than two formats glued together
    /// by a string, because the separator between a date and a time is the locale's, not ours:
    /// the word sits in a different place in each language.
    ///
    /// The date half is `.abbreviated` rather than `.numeric` because a bare "7/15/2026" is
    /// ambiguous outside the US while an abbreviated one is not.
    var dateTimeText: String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }
}
