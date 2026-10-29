import Foundation

public enum CalendarPolicy {
    /// Ongoing events take priority. All-day entries never occupy the countdown.
    public static func upcoming(_ events: [CalendarEvent], now: Double, limit: Int = 8) -> [CalendarEvent] {
        Array(events.filter {
            !$0.isAllDay && !$0.isCancelled && $0.start.isFinite && $0.end.isFinite &&
            $0.end > $0.start && $0.end > now && $0.start < now + 7 * 86_400
        }.sorted {
            let leftOngoing = $0.start <= now
            let rightOngoing = $1.start <= now
            if leftOngoing != rightOngoing { return leftOngoing }
            let left = leftOngoing ? $0.end : $0.start
            let right = rightOngoing ? $1.end : $1.start
            return left == right ? $0.id < $1.id : left < right
        }.prefix(max(0, limit)))
    }

    /// Only HTTPS meeting links from known providers can be opened by the helper.
    public static func meetingURL(in text: String) -> URL? {
        let pattern = #"https://[^\s<>\"\)\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let bounded = String(text.prefix(32_768))
        let range = NSRange(bounded.startIndex..., in: bounded)
        for match in regex.matches(in: bounded, range: range) {
            guard let matchRange = Range(match.range, in: bounded),
                  let url = URL(string: String(bounded[matchRange])),
                  url.absoluteString.utf8.count <= 2048,
                  url.user == nil, url.password == nil,
                  let host = url.host?.lowercased(),
                  ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
                    .contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
            return url
        }
        return nil
    }
}
