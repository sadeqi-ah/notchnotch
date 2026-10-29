# Music extension

The React activity connects to its own native adapter using only `ConnectionStream` and `JSONRPCClient`. The host contains no Spotify/Apple Music discovery or control code. `MusicPlayer`, `Artwork`, `Waveform` and the playback data types remain shared UI components.

Open Music and choose **Connect music** to start the helper after session consent. It reads playback from players whose Automation permission is already granted. **Connect Spotify** and **Connect Apple Music** request macOS permission explicitly; during playback, open **Players** to reach these controls. A disconnected helper requires an explicit reconnect. Nothing launches a player just to discover a track.

`build.mjs` compiles `helper-src` as the separate `MusicAdapter` target, packages its executable and Automation description into `helpers/MusicAdapter.app`, and signs that bundle for local development. Run `node scripts/build-extensions.mjs` from the repository root. Restart development after changing helper Swift sources. A packaged extension includes its compiled helper; the host needs neither the sources nor a compiler at runtime. The SwiftPM target reuses the shared UI data/feedback libraries, and has no dependency on the host application target.

## Adapter contract

The `player` manifest connection uses bounded JSONL over stdio, with JSON-RPC 2.0 envelopes. Stdout contains protocol messages only; EOF terminates the helper and its polling tasks. Messages fit the generic 64 KiB limit. Large embedded artwork is resized or omitted to keep playback updates deliverable.

| Method | Parameters | Result |
| --- | --- | --- |
| `music/getState` | None | Current status |
| `music/connect` | `{ player: "com.spotify.client" \| "com.apple.Music" }` | Status after the permission request |
| `music/command` | `{ command, value? }` | `null` once queued; later failures appear in status |
| `music/state` | Status, sent as a notification | No response |

Status contains optional `state` (`NowPlayingState`), an `authorized` array of source identifiers, an `errors` object keyed by source, and optional `commandError`. Every notification is a complete status snapshot. Query `music/getState` after connecting to recover the current state. The extension treats transport failure separately from player/Automation errors.

Commands are `playPause`, `previous`, `next`, `seek`, `volume`, `shuffle`, `repeat` and `openPlayer`. Seek/volume values are normalized to `[0, 1]`; other commands take no value. Targets and operations are fixed in the adapter. There is no arbitrary-script method. Metadata reads and writes use direct public Apple events with a two-second deadline, independently of permission requests. This avoids AppleScript event-loop stalls in a headless helper. Playback writes retain immediate feedback and reconcile against fresh samples; old samples cannot replace a newer command.

Like any extension with `process`, this preview's native helper runs with the user's privileges. OS Automation consent is separate from the host's session consent. A moved/rebuilt helper may need a fresh Automation grant; follow the error shown inside the activity and review System Settings → Privacy & Security → Automation.
