# Extension API v1 — preview

An extension consists of `notchnotch.json` and `src/index.tsx`. `pnpm build:extensions` bundles it into `dist/extensions/<folder>/bundle.js`; the app runs that bundle in JavaScriptCore.

```json
{
  "id": "dev.example.timer",
  "name": "My timer",
  "version": "0.1.0",
  "apiVersion": 1,
  "entry": "bundle.js",
  "permissions": []
}
```

```tsx
import { useState } from "react";
import { Activity, Button, Symbol, Text } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

function Counter() {
  const [count, setCount] = useState(0);
  return (
    <Activity id="counter" title="Counter">
      <Activity.Compact
        leading={<Symbol name="plus.circle" />}
        trailing={<Text>{count}</Text>}
      />
      <Activity.Expanded>
        <Text size="title">{count} little steps</Text>
        <Button title="One more" onPress={() => setCount((value) => value + 1)} />
      </Activity.Expanded>
    </Activity>
  );
}
start(<Counter />);
```

## Surfaces

- `Activity`: stable `id`, human-readable `title`, optional `phase` (`active`, `paused`, `completed`), and `initialView` (`compact` by default).
- `Prompt`: stable `id`, `title`, and `initialView` (`expanded` by default). Its phase is always `pending`. Store the answer and unmount the prompt to resolve it. Skipping is an explicit extension action.
- `Activity.Compact` / `Prompt.Compact`: `leading` and `trailing` React content. Both belong to a single host click target. Keep the content short and noninteractive.
- `Activity.Expanded` / `Prompt.Expanded`: required detailed content. A surface without compact content must request `initialView="expanded"`.
- `Activity.Peek`: optional announcement with a stable event `id`, one-line `text` (up to 256 characters), and `duration` in seconds (1–10, default 4). Requires `Activity.Compact`.

The initial view is a presentation request. The host can defer it while another surface is open. Do not use mount/unmount repeatedly to force attention.

## Temporary announcements

The host supports three presentations: compact, peek, and expanded. A peek keeps the compact wings around the camera and briefly opens a text row below them. The row slides into the notch as the shell returns to compact. Clicking opens the full activity and cancels automatic dismissal; Escape or an outside click dismisses only the announcement. Hover does not expand a peek.

```tsx
<Activity.Peek
  id={track.playbackEventID}
  text={`${track.artist} • ${track.title}`}
  duration={4}
/>
```

Place this beside `Activity.Compact` and `Activity.Expanded`. Change the id for each new playback event, including replaying the same track. Keep it stable for progress ticks and metadata updates: ordinary renders neither restart the deadline nor replay a dismissed announcement. A new event replaces an existing peek and starts a fresh deadline. Events received while a full panel or hover preview is open are consumed silently; incoming expanded prompts take priority. After dismissal, the announced activity remains selected in compact mode. Removing the Peek, surface, or extension cancels its active announcement.

The timer demo requests readiness/completion announcements; paused surfaces do not automatically claim the notch. Completion announces automatically, and readiness can be previewed manually. Use **Preview announcement** in the menu bar to replay its current announcement.

## Components

| Component | Props |
| --- | --- |
| `Text` | children containing text/numbers, `tone`, `size` |
| `Symbol` | SF Symbol `name`, `tone` |
| `Progress` | `value` in `[0, 1]`, `tone` |
| `Button` | `title`, `onPress`, `tone`, `disabled` |
| `TextField` | controlled `value`, `onChange`, `placeholder` |
| `Row`, `Column` | children |

Tones: `primary`, `secondary`, `accent`, `success`, `warning`. Text sizes: `caption`, `body`, `title`, `timer`. The native host controls layout metrics, typography, window dimensions, and animation.

React hooks, promises, `setTimeout`, `setInterval`, and `console` are available. DOM components, CSS, `fetch`, Node built-ins, native modules, and arbitrary system access are not supported. API v1 accepts only the optional `media` permission; all other capabilities are rejected. The SDK is a local workspace package and is not published to npm yet.


## Music extension

Declare `"permissions": ["media"]` to receive brokered metadata from Spotify/Apple Music. The host asks for Automation consent through its **Connect** commands. `useNowPlaying()` returns the latest `NowPlayingState` or `null` when no connected player has a track. A paused surface should use `phase="paused"`: the host keeps it in the activity switcher but hides its compact wings.

```tsx
const state = useNowPlaying();
if (!state) return null;
return <Activity id="music" title={state.title.slice(0, 128)} phase={state.isPlaying ? "active" : "paused"}>
  <Activity.Compact leading={<Artwork source={state.artwork} />}
    trailing={<Waveform playing={state.isPlaying} source={state.artwork} />} />
  <Activity.Peek id={state.eventID} text={`${state.artist} • ${state.title}`.slice(0, 256)} />
  <Activity.Expanded><MusicPlayer state={state} onCommand={controlMedia} /></Activity.Expanded>
</Activity>;
```

Import these components/hooks from `@notchnotch/sdk`. `controlMedia({ command, value? })` supports `playPause`, `previous`, `next`, `shuffle`, `repeat`, `openPlayer`, plus `seek` and `volume` with values in `[0, 1]`. The host validates the capability and request before accessing a player. `MusicPlayer` is native UI with accessible transport buttons and an adjustable seek bar; no extension JavaScript can send arbitrary Apple events or execute scripts. The artwork component accepts approved HTTPS artwork CDNs and bounded JPEG/PNG data, not filesystem URLs. There is no generic networking capability.


## Idle hover selection

The resting notch remains hidden for paused extensions. On hover, the host reveals the current compact activity first, then a pending question, then the most recently used activity, then an extension-declared resumable fallback. Opening an activity or a genuine phase transition records recency; routine metadata/progress updates do not reorder it. Click and long hover open the same chosen surface. If no contextual surface exists, neutral hub icons open the activity hub instead.

An `Activity` may set `idlePreview` to opt into the resumable fallback; it must have `Activity.Compact`. This requests hover visibility only and never claims the resting notch. The music extension opts in when it has a track, so a paused song can be revealed even before the user has interacted with this host. Newly installed, unused timer/question launchers do not take priority merely because they are installed. Recency is local to the running host session and is cleared when a surface or extension disappears.
