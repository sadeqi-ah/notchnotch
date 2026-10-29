# Architecture

## Native host

`NotchNotch` is an accessory macOS application. A nonactivating `NSPanel` hosts SwiftUI content. Automatic presentation never calls `makeKey`; explicit user interaction can make the panel key for text input. Escape and clicks outside the panel collapse it. The panel is anchored using public `NSScreen` safe-area and auxiliary-area APIs and repositions when display configuration changes.

`PlatformState` owns presentation independently from extension lifecycle. Each surface key is `(extensionID, surfaceID)`. An extension snapshot replaces only that extension's surfaces. Revisions increase within one runner session; stale snapshots are ignored. Restarting an extension clears its revisions and surfaces.

A new expanded surface opens automatically only while the panel is collapsed. Once an activity is open, incoming prompts remain pending and appear in the switcher/waiting count. Routine re-renders never reopen a dismissed prompt. Resolving a selected prompt removes it and returns the host to compact mode. Closing the panel never removes a surface or supplies an answer.

The host displays one active activity across the two notch wings at a time. All other activities remain available in the expanded switcher. The physical camera area is always reserved as an empty center gap.

Activities may also supply optional `peek` content: an event id, a short text line, and a duration of 1–10 seconds (the SDK defaults to four). `PlatformState` tracks the active event and a fixed expiry deadline. New event ids trigger the intermediate peek presentation only when no expanded panel or hover preview is open. Routine snapshots update text without extending the deadline, and ignored events are not replayed when a panel closes. A replacement event gets its own deadline. Expanded prompts take priority; explicit open/close, removal of peek content, and extension removal cancel the active peek. Paused surfaces remain in the switcher without claiming compact space; pausing cancels an automatic announcement. `AppModel` maintains one cancellable task per deadline and guards it against replacement, so an old timer cannot close a newer announcement or a panel opened by the user.

### Silhouette and motion

The peek body is 46 points taller than the camera, with an intermediate width and corner radii. Its compact wings stay visible and move inward as the lower text row fades and slides upward. The same silhouette and presentation enum drive rendering and pointer routing.

The shape is visually reconstructed from the installed Tuneful app, without its source code or assets. On the tested display the reference's open body is roughly 384 points wide with outward top shoulders and larger lower corners. `NotchSilhouette` draws those concave shoulders explicitly; a rounded rectangle cannot create this attachment to the screen edge.

A transparent window reserves room for all three states and the shadow. It grows when taller content needs more space, preserving the screen's top-center anchor, and retains that room for subsequent spring transitions. SwiftUI animates body width, height, shoulder radius, and lower radius together, using an interruptible spring (0.44 response / 0.82 damping opening; 0.36 / 0.9 closing). Content fades and slightly deblurs into place after the shell begins to expand. Closing fades content sooner than the silhouette finishes shrinking. These timing values are a reconstruction of the observed feel, not Tuneful's internal parameters.

**The notch must never scroll.** Expanded content uses an intrinsically sized vertical stack with no scroll container, height cap, or expanded-text line limit. The full measured height, rounded up to avoid subpixel clipping, determines the silhouette height; the window reserves enough space for all of it plus its shadow before expansion. Smaller content shrinks the visible body while the transparent canvas keeps its reserved height so the spring is not clipped. Timer/prompt content fits a compact body without the old brand header, tab pills, or divider. Activity navigation uses page indicators and a compact menu in the top-left wing.

Mouse routing follows the visible target path, not the transparent window rectangle. Global/local pointer monitors set `ignoresMouseEvents` outside the silhouette so desktop clicks pass through. The host has idle, compact, hovered, peek, and expanded presentations. Idle draws no shell or shadow; the activation region extends six points below the physical camera. Short hover highlights immediately, enlarging an active body by 12 points horizontally and four vertically (an idle body reveals 36-point wings on each side and a 10-point lower lip). `HoverState` opens after 850 ms and closes a hover preview after a 180 ms exit grace. Pointer monitors plus a 100 ms fallback sample cover ordinary movement, pointer warps and shape changes; transparent regions still pass clicks through. Compact playback has no shadow, while hover, peek, and expanded states have progressively elevated shadows. Explicit user interaction pins the activity; closing suppresses hover reopening until the pointer leaves. Automatic/hover opening never requests keyboard focus. Reduce Motion disables spring geometry, scaling, and blur while retaining a brief opacity change.

## Runner and React

Each bundled extension has a dedicated Swift `ExtensionRunner` process. It hosts one JavaScriptCore context on its main thread. The app does not forward its shell environment into the runner. App shutdown closes runner stdin and terminates its child processes; EOF also shuts down the runner.

The TypeScript bundle contains React, a private custom reconciler, the extension, and runtime glue. The SDK uses host components rather than React DOM. Each React commit produces one complete JSON snapshot. Functions stay in a runner-local action registry; only action identifiers cross the wire. Registry entries are replaced with each committed tree, so removed controls cannot invoke stale callbacks.

Native buttons and fields send an action identifier and optional text value. The reconciler processes these as discrete events and sends a new snapshot. Stable node identifiers preserve native text-field state while React updates props. Timers use the runner's Foundation run loop. Timer callbacks are retained in main-actor state and removed when canceled or the runtime stops.

React 19.3.1 and react-reconciler 0.34.0 are pinned together. The reconciler API is experimental; upgrades require running native integration tests.

## Transport and validation

Transport is newline-delimited UTF-8 JSON over child stdin/stdout. Console output uses structured log messages, never unframed stdout. Stderr reports runner startup failures. Every message carries protocol version 1 and an extension identifier where applicable.

The host validates identity, protocol version, revision, surface contract, node types, and bounded trees before changing state. Limits are 256 KiB/message, 16 surfaces/snapshot, 512 UI nodes/snapshot, and nesting depth 16. Progress values must be finite and between 0 and 1. Text events are capped at 4096 characters. An invalid snapshot or runtime error removes only that extension's surfaces and offers restart through the menu.

`schemas/` documents the wire contract. Swift and TypeScript models are currently handwritten, not generated. Host validation and real runner tests exercise the contract. A generator can replace duplication once the schema settles.

## Trust and omitted capabilities

The app loads only its bundled examples (or the explicit development directory). No extension installation API is exposed. Permission lists may contain `local-network` and `process`. JavaScriptCore has no Node globals or general filesystem/network/process primitives. Named connection declarations can request brokered loopback HTTP, WebSocket messages or fixed JSONL subprocesses after explicit session consent. This is a constrained API surface, not an OS security sandbox.

Before arbitrary third-party code is supported, add an OS-enforced runner/helper sandbox, startup/liveness timeouts, global CPU/memory/message-rate limits, and verified bundle installation. A blocked or malicious runner can currently hang or flood its pipe; process separation and per-connection limits alone do not solve resource exhaustion. Do not advertise this preview as safe for untrusted plugins.

### Generic connection broker

`NotchConnections.ConnectionBroker` belongs to one extension runner and immutable manifest. It checks extension identity, declared destinations and transport-specific permissions, asks the host for consent to the concrete target, and emits correlated responses and session-tagged events. Application payloads remain opaque JSON. Application-specific protocols and routing live in the extensions.

HTTP uses a dedicated ephemeral URLSession with redirects disabled, no cookies/cache/proxy and bounded UTF-8 responses. Only explicit IPv4/IPv6 loopback destinations are accepted; WebSockets have fixed manifest endpoints and separate long-lived sessions. Stdio uses a dedicated process, bounded JSONL decoding, fixed arguments, canonical bundle-path checks and a minimal environment. A process grant trusts the native adapter with the user's filesystem/network privileges; it does not sandbox it. Stream messages have a 64 KiB limit and 256-message-per-second limit, pending commands are bounded, and session ids reject stale messages after reconnect. Runner input is serialized off the UI thread with bounded backpressure.

Stopping/reloading an extension or using the disconnect command cancels tasks, closes sockets, terminates immediate helper processes and clears session grants. The SDK correlates responses, rejects pending requests on disconnect and leaves reconnection and application-level decisions to the extension. See [Connections](connections.md) for transport/lifecycle details and limitations.


## Music extension and native adapter

`extensions/music` owns its React activity and a bundled `MusicAdapter.app`. The extension opens its declared `player` stdio connection explicitly; host session consent is identical to any other native helper. `ConnectionStream`/`JSONRPCClient` carry the extension's `music/getState`, `music/connect`, `music/command` and `music/state` messages. The native host only validates generic connection envelopes. There is no privileged media transport, MusicProvider instance, player-specific menu or Automation command in the host.

The helper sources live in `extensions/music/helper-src`. `MusicProvider` reads fixed public Apple-event properties on a dedicated actor with a two-second deadline for each complete sample. It uses no AppleScript engine. Permission requests and playback writes have separate actors, keeping a slow read from blocking connection setup or controls. It checks existing Automation grants silently; the extension's explicit Connect commands request macOS consent. It polls only running Spotify/Apple Music processes, once per second while playing and every three seconds while paused. Distributed player notifications trigger refreshes. Source selection stays stable when both apps are open; brief read failures retain the last good sample for up to five seconds. Helper JSONL is bounded to the generic 64 KiB limit, including inline artwork and errors.

`MusicPlayer`, `Artwork`, `Waveform`, `NowPlayingState` and `PlaybackFeedback` are reusable UI/data components. The player renders supplied state and sends ordinary UI actions back to the extension. Source identifiers are opaque strings, not host-owned application identities. Metadata event ids stay stable across progress/artwork updates, and paused music remains available in the activity switcher. The native artwork renderer uses approved CDN sources or bounded inline JPEG/PNG data, with 64 cached covers and shared in-flight loads. Apple Music thumbnails are produced by the helper before crossing the generic bridge.

`extensions/music/build.mjs` compiles the sample helper as a separate SwiftPM executable target, packages it with its Automation usage description and signs its bundle. The extension builder supports an optional build module for any extension; the running host never executes build modules. Production distribution still requires the ordinary signing and helper trust work described above.

`PlatformState.hoverSurface` owns context selection independently of resting presentation: compact activity → pending prompt → most recently interacted/previously active surface → explicit `idlePreview` fallback → neutral activity hub. The host uses this same target for the wings, long-hover content, and click destination, so a paused music cover cannot open an unrelated demo. Routine snapshots never change recency. Music metadata starts below the physical camera with a six-point clearance; artwork stays in its original top-left position.


### Playback intent and confirmation

`PlaybackFeedback` is shared by the native player and the extension helper. Seek, play/pause, shuffle, repeat, and volume changes appear locally as soon as the user interacts. Releasing the seek gesture transfers its value into pending intent rather than dropping back to the last polled position. A fresh sample acknowledges only the matching fields; old timestamps, earlier seek targets, and intermediate toggle states cannot overwrite newer intent. Pending position includes a local clock, so playing continues to advance and Pause freezes immediately. Intent is cleared on track changes, rolls back on explicit failure, or expires after three seconds if the player never confirms it.

Spotify and Apple Music commands are fixed public Apple events on a dedicated serial actor, independent of metadata reads. Property specifiers are coerced from Apple-event records rather than reconstructed from raw record bytes. Play/Pause sends an explicit desired play or pause state; rapid requests are serialized in arrival order. A subsequent command is sent without waiting for the previous command's metadata refresh. Both players use their published Apple-event dictionaries and receive the same optimistic presentation and confirmation protection.

The helper provider tags metadata reads with a command revision and discards reads that started before a newer request. A refresh requested during an existing read is queued rather than dropped. After a write, unacknowledged intent triggers short confirmation reads, returning to the normal polling interval once confirmed. Command failures are shown in the music panel; a failed older command cannot clear a newer pending request.
