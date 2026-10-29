import AppKit
import EventKit
import CryptoKit
import CalendarSupport
import NotchProtocol

struct CalendarChoice: Encodable, Equatable {
    let id: String
    let title: String
    let selected: Bool
}

struct CalendarStatus: Encodable, Equatable {
    var authorization: String
    var calendars: [CalendarChoice] = []
    var events: [CalendarEvent] = []
    var error: String?
}

@MainActor
final class CalendarSource {
    private let store = EKEventStore()
    private let preferences = UserDefaults(suiteName: "dev.notchnotch.calendar.adapter") ?? .standard
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var selectedIDs: Set<String>?
    private(set) var status = CalendarStatus(authorization: "notDetermined")
    var onChange: ((CalendarStatus) -> Void)?

    init() {
        selectedIDs = preferences.stringArray(forKey: "selectedCalendarIDs").map(Set.init)
    }

    func start() {
        refresh()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func connect() async {
        do {
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = try await store.requestFullAccessToEvents()
            }
            refresh()
        } catch {
            status = CalendarStatus(authorization: authorization, error: String(error.localizedDescription.prefix(1024)))
            onChange?(status)
        }
    }

    func select(_ ids: [String]) throws {
        guard authorization == "authorized" else { throw ProtocolError.invalid("Connect Calendar first") }
        let known = Set(store.calendars(for: .event).map(\.calendarIdentifier))
        guard ids.count <= 64, Set(ids).isSubset(of: known) else { throw ProtocolError.invalid("Unknown calendar selection") }
        selectedIDs = Set(ids)
        preferences.set(ids, forKey: "selectedCalendarIDs")
        refresh()
    }

    func refresh() {
        var next = CalendarStatus(authorization: authorization)
        if next.authorization == "authorized" {
            let calendars = store.calendars(for: .event).sorted {
                $0.title == $1.title ? $0.calendarIdentifier < $1.calendarIdentifier : $0.title < $1.title
            }
            // Bound both the settings tree and the JSONL payload.
            let visible = Array(calendars.prefix(64))
            next.calendars = visible.map {
                .init(id: $0.calendarIdentifier, title: String($0.title.prefix(128)),
                      selected: selectedIDs?.contains($0.calendarIdentifier) ?? true)
            }
            let enabled = visible.filter { selectedIDs?.contains($0.calendarIdentifier) ?? true }
            if !enabled.isEmpty {
                let now = Date.now
                let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 86_400), calendars: enabled)
                let events = store.events(matching: predicate).compactMap { event -> CalendarEvent? in
                    guard !event.isAllDay, event.status != .canceled,
                          event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true,
                          let start = event.startDate, let end = event.endDate else { return nil }
                    let identity = (event.calendarItemIdentifier) + ":" + String(start.timeIntervalSince1970)
                    let id = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                    let linkText = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
                    return CalendarEvent(id: id, title: event.title ?? "", calendarID: event.calendar.calendarIdentifier,
                        calendarTitle: event.calendar.title, start: start.timeIntervalSince1970, end: end.timeIntervalSince1970,
                        location: event.location, meetingURL: CalendarPolicy.meetingURL(in: linkText)?.absoluteString)
                }
                next.events = CalendarPolicy.upcoming(events, now: now.timeIntervalSince1970)
            }
        } else if next.authorization == "denied" || next.authorization == "restricted" || next.authorization == "writeOnly" {
            next.error = "Calendar access is unavailable. Allow full access in System Settings → Privacy & Security → Calendars, then reconnect."
        }
        guard next != status else { return }
        status = next
        onChange?(next)
    }

    func openCalendar() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            throw ProtocolError.invalid("Calendar is not installed")
        }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func join(_ id: String) throws {
        refresh()
        guard let event = status.events.first(where: { $0.id == id }),
              let value = event.meetingURL, let url = CalendarPolicy.meetingURL(in: value),
              NSWorkspace.shared.open(url) else { throw ProtocolError.invalid("This event no longer has an available meeting link") }
    }

    private var authorization: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: "authorized"
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .writeOnly: "writeOnly"
        default: "denied"
        }
    }
}
