import Foundation
import Testing
@testable import CalendarSupport

private func event(_ id: String, start: Double, end: Double, allDay: Bool = false, cancelled: Bool = false) -> CalendarEvent {
    CalendarEvent(id: id, title: id, calendarID: "work", calendarTitle: "Work", start: start, end: end,
                  isAllDay: allDay, isCancelled: cancelled)
}

@Test func ongoingEventsWinAndExpiredCancelledAndAllDayEventsAreExcluded() {
    let events = [
        event("later", start: 200, end: 300), event("expired", start: 50, end: 100),
        event("ongoing", start: 50, end: 150), event("all-day", start: 0, end: 86_400, allDay: true),
        event("cancelled", start: 101, end: 200, cancelled: true), event("invalid", start: 200, end: 150),
    ]
    #expect(CalendarPolicy.upcoming(events, now: 100).map(\.id) == ["ongoing", "later"])
    #expect(CalendarPolicy.upcoming(events, now: 150).map(\.id) == ["later"])
}

@Test func overlappingEventsChooseTheSoonestEndingAndResultsAreBounded() {
    let events = [event("long", start: 0, end: 500), event("short", start: 50, end: 150),
                  event("future", start: 200, end: 300), event("outside", start: 700_000, end: 700_100)]
    #expect(CalendarPolicy.upcoming(events, now: 100, limit: 2).map(\.id) == ["short", "long"])
    #expect(CalendarPolicy.upcoming(events, now: 100, limit: 0).isEmpty)
}

@Test func meetingLinksMustUseHTTPSAndAnExactProviderDomain() {
    #expect(CalendarPolicy.meetingURL(in: "Join https://meet.google.com/abc-defg-hij")?.host == "meet.google.com")
    #expect(CalendarPolicy.meetingURL(in: "(https://us02web.zoom.us/j/123)")?.path == "/j/123")
    #expect(CalendarPolicy.meetingURL(in: "https://zoom.us.evil.example/j/123") == nil)
    #expect(CalendarPolicy.meetingURL(in: "https://zoom.us@evil.example/j/123") == nil)
    #expect(CalendarPolicy.meetingURL(in: "http://meet.google.com/abc") == nil)
    #expect(CalendarPolicy.meetingURL(in: "file:///tmp/meeting.app") == nil)
    #expect(CalendarPolicy.meetingURL(in: "https://example.com https://teams.microsoft.com/l/meetup-join/abc")?.host == "teams.microsoft.com")
}
