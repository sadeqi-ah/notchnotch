import Foundation

public struct CalendarEvent: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let calendarID: String
    public let calendarTitle: String
    public let start: Double
    public let end: Double
    public let location: String?
    public let meetingURL: String?
    public let isAllDay: Bool
    public let isCancelled: Bool

    public init(id: String, title: String, calendarID: String, calendarTitle: String,
                start: Double, end: Double, location: String? = nil, meetingURL: String? = nil,
                isAllDay: Bool = false, isCancelled: Bool = false) {
        self.id = id
        self.title = String((title.isEmpty ? "Untitled event" : title).prefix(256))
        self.calendarID = calendarID
        self.calendarTitle = String(calendarTitle.prefix(128))
        self.start = start; self.end = end
        self.location = location.map { String($0.prefix(256)) }
        self.meetingURL = meetingURL
        self.isAllDay = isAllDay; self.isCancelled = isCancelled
    }
}
