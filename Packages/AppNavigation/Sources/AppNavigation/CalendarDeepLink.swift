//
//  CalendarDeepLink.swift
//  AppNavigation
//

import Foundation

/// What a link asked for, when it cannot be had.
///
/// A value rather than a message: this package has no strings and should not acquire any, so
/// *whether* to complain and *what to say* are kept apart — the navigation decides that a link
/// failed and with what cause, and the view that presents the alert decides the words.
public enum DeepLinkFailure: Equatable, Hashable, Sendable {
    /// The link named a calendar that is not there.
    ///
    /// Carries the id because it is the one thing the user can check against what they tapped:
    /// a link shared before the calendar was deleted is a very ordinary way to arrive here, and
    /// seeing the id they were sent is more use than a bare "not found".
    case noSuchCalendar(id: Int64)
}

/// A link from outside the app that names somewhere to go.
///
/// This is a *parser*, not a navigator: it turns a `URL` into an intent and stops there. What
/// happens next — whether that calendar still exists, whether the user may leave the one they
/// are looking at — is answered by the navigation, and answering either question here would
/// need this package to depend on storage and on the app's write guard, which it deliberately
/// does not.
///
/// Two spellings are accepted, because both are natural to type and there is no reason to
/// make a caller choose one:
///
/// - REST-shaped, id as a path segment: `pincalapp://calendars/4`
/// - Query-shaped, id as a parameter: `pincalapp://calendars?calendarid=4`
///
/// When a link carries both, the **path wins**: it is the more specific of the two, and a link
/// that names an id twice with different values is malformed rather than ambiguous-by-design.
public enum CalendarDeepLink: Equatable, Hashable, Sendable {
    /// Open the calendar with this id.
    case calendar(id: Int64)

    /// The scheme this app answers to.
    ///
    /// Matched case-insensitively, because `URLComponents` does not normalise it and a scheme
    /// typed by hand on a keyboard is as likely to arrive as `PinCalApp://`.
    public static let scheme = "pincalapp"

    /// The host that names a calendar rather than some other destination.
    public static let host = "calendars"

    /// The query parameter carrying the id in the query-shaped spelling.
    public static let idQueryItemName = "calendarid"

    /// The calendar this link names.
    public var calendarID: Int64 {
        switch self {
        case let .calendar(id): return id
        }
    }

    /// Parses `url`, or returns `nil` if it is not a link this app acts on.
    ///
    /// `nil` is the answer for everything this app does not recognise — another app's scheme,
    /// an unknown host, a missing or malformed id — and deliberately so: a link can come from
    /// anywhere, including a web page, and an unrecognised one is not an error to be reported
    /// to the user. It is simply not for us.
    ///
    /// An id must be a positive `Int64`. Zero and negatives are rejected here rather than being
    /// carried as far as the navigation, which has no sentinel for "no calendar" — it would
    /// happily open one and leave a detail column showing nothing, which is the failure
    /// `RootNavigation.closeCalendarIfSelected` exists to clean up after.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.scheme?.lowercased() == Self.scheme,
              components.host?.lowercased() == Self.host
        else {
            return nil
        }
        guard let raw = Self.pathID(in: components) ?? Self.queryID(in: components),
              let id = Int64(raw),
              id > 0
        else {
            return nil
        }
        self = .calendar(id: id)
    }

    /// The id from the REST-shaped spelling, `pincalapp://calendars/4`.
    ///
    /// The first non-empty segment, and later segments are ignored rather than rejected: a
    /// trailing `/` is the common accidental case, and it names the same calendar as without.
    private static func pathID(in components: URLComponents) -> String? {
        components.path
            .split(separator: "/")
            .first
            .map(String.init)
    }

    /// The id from the query-shaped spelling, `pincalapp://calendars?calendarid=4`.
    ///
    /// Case-insensitive on the name too, for the same reason as the scheme. An empty value is
    /// `nil` rather than `""`, so `?calendarid=` falls through to the `Int64` check and is
    /// rejected as the malformed link it is, instead of parsing as zero.
    private static func queryID(in components: URLComponents) -> String? {
        components.queryItems?
            .first { $0.name.lowercased() == idQueryItemName }?
            .value
    }
}
