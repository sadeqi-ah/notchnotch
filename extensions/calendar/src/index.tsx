import { useEffect, useMemo, useRef, useState } from "react";
import { Activity, Button, ConnectionStream, JSONRPCClient, Progress, Row, Settings, Symbol, Text } from "@notchnotch/sdk";
import type { JSONValue } from "@notchnotch/protocol";
import { start } from "@notchnotch/runtime";

interface CalendarEvent {
  id: string;
  title: string;
  calendarID: string;
  calendarTitle: string;
  start: number;
  end: number;
  location?: string;
  meetingURL?: string;
}
interface CalendarStatus {
  authorization: string;
  calendars: { id: string; title: string; selected: boolean }[];
  events: CalendarEvent[];
  error?: string;
}

function time(value: number) {
  return new Date(value * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
function date(value: number) {
  return new Date(value * 1000).toLocaleDateString([], { weekday: "short", month: "short", day: "numeric" });
}
function countdown(seconds: number, compact = false) {
  if (seconds < 60) return `${Math.max(1, Math.ceil(seconds))}${compact ? "s" : " sec"}`;
  const minutes = Math.ceil(seconds / 60);
  if (minutes < 60) return `${minutes}${compact ? "m" : " min"}`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return `${hours}h${rest ? ` ${rest}m` : ""}`;
}

function Calendar() {
  const rpc = useMemo(() => new JSONRPCClient(new ConnectionStream("calendar")), []);
  const [status, setStatus] = useState<CalendarStatus | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => Date.now() / 1000);
  const working = useRef(false);
  const generation = useRef(0);
  useEffect(() => {
    const stopNotifications = rpc.onNotification(({ method, params }) => {
      if (method === "calendar/state" && params && typeof params === "object" && !Array.isArray(params)) {
        setStatus(params as unknown as CalendarStatus);
        setNow(Date.now() / 1000);
      }
    });
    const stopStream = rpc.stream.subscribe((event) => {
      if (event.event === "closed") {
        generation.current++;
        setStatus(null);
        setError(event.error ?? "Calendar disconnected. Connect again to resume.");
      }
    });
    return () => {
      generation.current++;
      stopNotifications(); stopStream();
      void rpc.dispose().catch(() => {});
    };
  }, [rpc]);
  const authorized = status?.authorization === "authorized";
  const hasEvents = authorized && !!status?.events.length;
  useEffect(() => {
    if (!hasEvents) return;
    const timer = setInterval(() => setNow(Date.now() / 1000), 1000);
    return () => clearInterval(timer);
  }, [hasEvents]);

  async function request(method: string, params?: JSONValue) {
    if (working.current) return;
    working.current = true;
    const current = generation.current;
    setBusy(true); setError("");
    try {
      const result = await rpc.request<CalendarStatus | null>(method, params, 120_000);
      if (generation.current !== current) return;
      if (result) setStatus(result);
      setNow(Date.now() / 1000);
    } catch (failure) {
      if (generation.current !== current) return;
      setError(String(failure).slice(0, 1024));
      if (method === "calendar/connect") {
        setStatus(null);
        await rpc.disconnect().catch(() => {});
      }
    } finally { working.current = false; setBusy(false); }
  }

  function toggleCalendar(id: string) {
    if (!status) return;
    const ids = status.calendars.filter((calendar) => calendar.id === id ? !calendar.selected : calendar.selected)
      .map((calendar) => calendar.id);
    void request("calendar/select", { ids });
  }

  const events = authorized ? (status?.events ?? []).filter((event) => event.end > now) : [];
  const event = events[0];
  const ongoing = !!event && event.start <= now;
  const imminent = !!event && event.start - now <= 15 * 60;
  const remaining = event ? (ongoing ? event.end : event.start) - now : 0;
  const problem = error || status?.error;
  return <>
    <Settings>
      <Text tone="secondary">See your next event from the calendars on this Mac. Events are never edited.</Text>
      <Row>
        <Button title={authorized ? "Refresh calendars" : "Connect Calendar"} tone="accent" disabled={busy}
          onPress={() => { void request(authorized ? "calendar/getState" : "calendar/connect"); }} />
        <Button title="Open Calendar" disabled={busy} onPress={() => { void request("calendar/open"); }} />
      </Row>
      {busy ? <Text tone="secondary">{authorized ? "Updating Calendar…" : "Connecting to Calendar…"}</Text> : null}
      {problem ? <Text tone="warning">{problem.slice(0, 1024)}</Text> : null}
      {authorized ? <>
        <Text size="caption" tone="secondary">CALENDARS</Text>
        <Text tone="secondary">Choose the calendars to include. All-day and declined events are excluded.</Text>
        {status.calendars.map((calendar) => <Row key={calendar.id}>
          <Symbol name={calendar.selected ? "checkmark.circle.fill" : "circle"} tone={calendar.selected ? "success" : "secondary"} />
          <Button title={`${calendar.selected ? "Hide" : "Show"} ${calendar.title}`} disabled={busy}
            onPress={() => toggleCalendar(calendar.id)} />
        </Row>)}
        {!status.calendars.length ? <Text tone="secondary">No calendars found. Add an account in Calendar, then refresh.</Text> : null}
        {!events.length ? <Text tone="secondary">No upcoming timed events in your selected calendars for the next seven days.</Text> : null}
        <Text tone="secondary">The notch appears 15 minutes before an event and stays until it ends. Hover to preview an event further away.</Text>
      </> : null}
    </Settings>
    {event ? <Activity id="next-event" title={event.title.slice(0, 128)} phase={imminent ? "active" : "paused"} idlePreview>
      <Activity.Compact leading={<Symbol name={ongoing ? "calendar.badge.clock" : "calendar"} />}
        trailing={<Text size="caption">{countdown(remaining, true)}</Text>} />
      {imminent ? <Activity.Peek id={`${event.id}:${ongoing ? "started" : "soon"}`}
        text={`${ongoing ? "Now" : "Up next"} • ${event.title}`.slice(0, 256)} /> : null}
      <Activity.Expanded>
        <Row><Symbol name="calendar" /><Text size="caption" tone="secondary">{ongoing ? "IN PROGRESS · ENDS IN" : "NEXT EVENT · STARTS IN"}</Text></Row>
        <Text size="timer">{countdown(remaining)}</Text>
        <Text size="title">{event.title.slice(0, 180)}</Text>
        <Text tone="secondary">{`${date(event.start)} · ${time(event.start)} – ${time(event.end)}`}</Text>
        <Text size="caption" tone="secondary">{event.calendarTitle}</Text>
        {event.location && !event.location.startsWith("https://") ? <Text tone="secondary">{event.location.slice(0, 160)}</Text> : null}
        {ongoing ? <Progress value={Math.max(0, Math.min(1, (now - event.start) / (event.end - event.start)))} /> : null}
        <Row>
          {event.meetingURL ? <Button title="Join meeting" tone="accent" disabled={busy}
            onPress={() => { void request("calendar/join", { id: event.id }); }} /> : null}
          <Button title="Open Calendar" disabled={busy} onPress={() => { void request("calendar/open"); }} />
        </Row>
        {error ? <Text tone="warning">{error.slice(0, 256)}</Text> : null}
        {events[1] ? <Text size="caption" tone="secondary">{`${events[1].start <= now ? "ALSO NOW" : "THEN"} · ${date(events[1].start)} ${time(events[1].start)} · ${events[1].title.slice(0, 96)}`}</Text> : null}
      </Activity.Expanded>
    </Activity> : null}
  </>;
}
start(<Calendar />);
