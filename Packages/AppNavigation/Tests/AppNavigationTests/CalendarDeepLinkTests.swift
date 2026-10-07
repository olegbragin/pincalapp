
import Foundation
import Testing
@testable import AppNavigation

@Suite("CalendarDeepLink Tests")
struct CalendarDeepLinkTests {
    // MARK: - The two accepted spellings

    @Test("REST-shaped link names the calendar by path")
    func restShaped() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/4"))) == .calendar(id: 4))
    }

    @Test("Query-shaped link names the calendar by parameter")
    func queryShaped() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars?calendarid=4"))) == .calendar(id: 4))
    }

    @Test("The path wins when a link carries an id twice")
    func pathWinsOverQuery() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/4?calendarid=9"))) == .calendar(id: 4))
    }

    // MARK: - Not ours

    /// A link can arrive from anywhere. One that is not for this app is not an error to show
    /// anyone — it is simply not addressed to us, and must not navigate.
    @Test(
        "Links that are not ours parse to nothing",
        arguments: [
            "otherapp://calendars/4", // another scheme
            "https://calendars/4", // a web URL
            "pincalapp://other/4", // an unknown host
            "pincalapp://calendars", // no id at all
            "pincalapp://calendars/abc", // not a number
            "pincalapp://calendars/0", // zero is not a calendar
            "pincalapp://calendars/-1", // nor is a negative
            "pincalapp://calendars?calendarid=", // present but empty
            "pincalapp://calendars?other=4", // right host, wrong parameter
            "pincalapp://calendars/99999999999999999999", // too large for Int64
        ]
    )
    func rejectsNonCalendarLinks(url: String) throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: url))) == nil)
    }

    // MARK: - Hand-typed URLs

    /// Schemes and hosts are case-insensitive per RFC, and `URLComponents` does not normalise
    /// them, so a hand-typed link must not be rejected for a capital letter.
    @Test("Scheme, host and parameter name are matched case-insensitively")
    func caseInsensitive() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "PINCALAPP://calendars/4"))) == .calendar(id: 4))
        #expect(try CalendarDeepLink(url: #require(URL(string: "PinCalApp://CALENDARS/4"))) == .calendar(id: 4))
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars?CalendarId=4"))) == .calendar(id: 4))
    }

    /// A trailing slash is the accidental half of "and then I pressed return twice", and it
    /// names the same calendar as the URL without it.
    @Test("A trailing slash names the same calendar")
    func trailingSlash() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/4/"))) == .calendar(id: 4))
        // Also on the query-shaped spelling, where the slash lands between the host and the `?`
        // and would otherwise be a path segment that reads as a non-numeric id.
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/?calendarid=4"))) == .calendar(id: 4))
    }

    @Test("An id is read as written, with no numeric surprises")
    func idFidelity() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/0"))) == nil)
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/007"))) == .calendar(id: 7))
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/ 4"))) == nil)
    }

    // MARK: - The parsed value

    @Test("The parsed id is readable back off the link")
    func calendarIDAccessor() throws {
        let link = try CalendarDeepLink(url: #require(URL(string: "pincalapp://calendars/12")))
        #expect(link?.calendarID == 12)
    }

    /// A reminder that the parse is where the decision to *ignore* a link is made — the enum
    /// has no "unrecognised" case, so there is nothing to accidentally navigate on later.
    @Test("An unrecognised link has no value to navigate to")
    func noValueForUnrecognised() throws {
        #expect(try CalendarDeepLink(url: #require(URL(string: "pincalapp://nope"))) == nil)
    }
}
