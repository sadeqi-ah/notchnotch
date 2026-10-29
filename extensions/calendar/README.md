# Calendar

Upcoming events from calendars already configured in macOS Calendar. Uses public EventKit APIs through an extension-owned native JSONL helper, with the same generic SDK as Music.

## Connect

Build/run the app, then choose **Settings & Extensions… → Calendar → Setup → Connect Calendar**. Approve the helper connection and macOS Calendar access. If access was denied, allow Calendar access for NotchNotch/NotchNotch Calendar in **System Settings → Privacy & Security → Calendars**, then reconnect. Connecting is explicit each runner session; macOS remembers its own grant.

The setup panel lists up to 64 calendars and lets you show/hide each one. Selection is remembered locally in the helper's `dev.notchnotch.calendar.adapter` preferences. It stores identifiers only, not event contents. Add accounts through Calendar's normal settings; no separate Google, Exchange or iCloud login is needed here.

## Notch behavior

- Reads the next seven days; all-day, cancelled, declined and finished events are excluded.
- Ongoing events come first, ordered by soonest ending, followed by future events in start order. Recurring occurrences have distinct stable identifiers.
- Shows the next event with a live countdown, local date/time, calendar, location, and the following event when available.
- Events further than 15 minutes away stay paused and can be previewed on hover. An event claims the notch 15 minutes before it starts and stays until it ends.
- A short announcement occurs when the event becomes imminent and when it starts. Per-second countdown updates keep the announcement identifier stable.
- **Open Calendar** opens the Calendar app. **Join meeting** opens an HTTPS link for Zoom, Google Meet, Teams or Webex found in the event URL, location or notes. The helper rechecks that the event/link still exists before opening it.
- With no upcoming events or no access, only the management setup panel remains. Disconnecting or disabling the extension clears its notch activity.

EventKit changes trigger a refetch; a 15-second poll handles permission and time changes. The React countdown uses wall-clock deadlines, including after wake. The helper returns at most eight events and bounds text/payload sizes. Event notes and attendees are not sent to the extension UI.

## Adapter protocol

The manifest declares a `calendar` stdio connection to `helpers/CalendarAdapter.app/Contents/MacOS/CalendarAdapter`. Requests and responses use JSON-RPC 2.0, one JSON value per line, with the host's 64 KiB message limit.

| Method | Parameters | Result |
| --- | --- | --- |
| `calendar/getState` | none | Current status; never prompts for access |
| `calendar/connect` | none | Requests access if undetermined, then returns status |
| `calendar/select` | `{ "ids": ["calendar-id"] }` | Saves selected calendars and returns status; `[]` selects none |
| `calendar/open` | none | Opens Calendar; returns `null` |
| `calendar/join` | `{ "id": "occurrence-id" }` | Opens the current occurrence's supported meeting link; returns `null` |

Status has `authorization` (`notDetermined`, `authorized`, `denied`, `restricted`, `writeOnly`), `calendars` (`id`, `title`, `selected`), `events`, and optional `error`. Events have `id`, `title`, `calendarID`, `calendarTitle`, `start`/`end` (Unix seconds), optional `location` and `meetingURL`. The helper emits `calendar/state` notifications with status only when it changes. Unknown methods return `-32601`; invalid parameters/actions return `-32602`. There are no event write/delete methods.

macOS requires **full access** to read events even though this extension never changes them. Both helper and host include `NSCalendarsFullAccessUsageDescription` and the macOS compatibility usage key. The helper is signed ad hoc for local development, like Music; publishing requires stable signing and a separate distribution review.

## Validation

Swift tests cover event filtering, overlap priority, bounds and meeting URL validation. Runner integration tests cover explicit connection, calendar selection, distant/imminent/ongoing/ended events, permission revocation and disconnect. Helper protocol tests query status and reject invalid operations without requesting Calendar permission or opening apps. The actual macOS consent dialog and live account sync require checking on a Mac through the setup panel.
