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

The app loads only its bundled examples (or the explicit development directory). No extension installation API is exposed. Permission lists may contain only `media`. JavaScriptCore has no Node globals, and this host does not export filesystem/network/process APIs. This is a constrained API surface, not an OS security sandbox.

Before arbitrary third-party code is supported, add an OS-enforced runner sandbox, a host capability broker, startup/liveness timeouts, CPU/memory/message-rate limits, and verified bundle installation. A blocked or malicious runner can currently hang or flood its pipe; process separation alone does not solve resource exhaustion. Do not advertise this preview as safe for untrusted plugins.


## Music capability

`extensions/music` is a React extension using `useNowPlaying`, `Artwork`, `Waveform`, and `MusicPlayer`. The native `MusicProvider` serializes fixed AppleScript reads and commands on a dedicated actor, keeping Apple events off the UI thread. It never evaluates extension-supplied scripts. It checks existing Automation grants silently; explicit Connect commands ask macOS for consent. Only running Spotify/Apple Music processes are polled, once per second while playing and every three seconds while paused. Distributed player notifications trigger immediate refreshes. An active source remains stable when both apps are open; short read failures retain the last good sample for up to five seconds.

Only runners whose validated manifest declares `media` receive host-to-runner `media` updates or may issue `mediaCommand` messages. The broker validates a fixed command enum and normalized seek/volume values. These messages pass through the same bounded JSON transport; media updates can carry artwork beyond the ordinary 8 KiB user-event limit. Media updates include a stable playback event id and timestamp; progress and artwork updates never retrigger a peek. Paused music stays available to reopen while its compact surface is hidden.

The native renderer supplies a 60-point album cover, title/artist, a tinted seek track, and transport controls in an intrinsically sized player. Album artwork is fetched through the host renderer only from approved Spotify/Apple artwork CDNs or bounded inline image data, with 64 cached covers and shared in-flight loads. Apple Music artwork is converted to a small JPEG before crossing the bridge. The waveform is a decorative playback indicator, not captured audio; Reduce Motion stops its animation.


`PlatformState.hoverSurface` owns context selection independently of resting presentation: compact activity → pending prompt → most recently interacted/previously active surface → explicit `idlePreview` fallback → neutral activity hub. The host uses this same target for the wings, long-hover content, and click destination, so a paused music cover cannot open an unrelated demo. Routine snapshots never change recency. Music metadata starts below the physical camera with a six-point clearance; artwork stays in its original top-left position.


### Playback intent and confirmation

`PlaybackFeedback` is shared by the native player and the host broker. Seek, play/pause, shuffle, repeat, and volume changes appear locally as soon as the user interacts. Releasing the seek gesture transfers its value into pending intent rather than dropping back to the last polled position. A fresh sample acknowledges only the matching fields; old timestamps, earlier seek targets, and intermediate toggle states cannot overwrite newer intent. Pending position includes a local clock, so playing continues to advance and Pause freezes immediately. Intent is cleared on track changes, rolls back on explicit failure, or expires after three seconds if the player never confirms it.

Spotify commands are fixed public Apple events on a dedicated serial actor, independent of metadata reads. Property specifiers are coerced from Apple-event records rather than reconstructed from raw record bytes. Play/Pause sends an explicit desired play or pause state; rapid requests are serialized in arrival order. A subsequent command is sent without waiting for the previous command's metadata refresh. Apple Music retains the fixed scripting command transport and receives the same optimistic presentation and confirmation protection.

The provider tags metadata reads with a command revision and discards reads that started before a newer request. A refresh requested during an existing read is queued rather than dropped. After a write, unacknowledged intent triggers short confirmation reads, returning to the normal polling interval once confirmed. Command failures are shown in the music panel; a failed older command cannot clear a newer pending request.
