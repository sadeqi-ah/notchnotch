# NotchNotch

A shared space in the Mac notch for live activities and quick questions.

This is a working developer preview: a native AppKit/SwiftUI host, a separate JavaScriptCore process for each extension, a React renderer, and bundled Music and Calendar extensions. It is intended for local development with trusted code.

## Run

Requires macOS 14+, Xcode 16+ (or a compatible Swift 6 toolchain), Node.js 22+, and pnpm 11.5.3.

```sh
pnpm install
pnpm dev
```

The app appears at the top of the built-in notched display, or as a small pill on the main display when no notch is available. It has a menu bar icon and no Dock icon.

- When nothing is active, the app is completely hidden behind the physical notch. Installed or paused extensions do not keep it visible.
- A short hover reveals the idle notch, or slightly enlarges an active notch and adds a soft shadow. Dwell for 850 ms to open its full view; leaving closes a hover preview after 180 ms. Click to pin it open.
- Open **Settings & Extensions… → Extensions → Music → Setup**. Choose **Connect Spotify** or **Connect Apple Music** there to start its bundled helper and request access. Music appears in the notch when a connected player has a track; its notch UI contains playback controls. The music extension shows real album artwork, a playback waveform, title/artist, seek bar, shuffle, previous/play/next, and repeat controls.
- Open **Settings & Extensions… → Calendar → Setup → Connect Calendar** to grant access to calendars on this Mac. Choose which calendars to include. The next timed event has a live countdown, date/time, calendar and location, plus **Join meeting** when it has a supported meeting link. It appears 15 minutes before the event and stays until it ends; hover previews events further away. All-day, cancelled and declined events are excluded. No events are edited.
- Pausing hides an unpinned music activity; a new song briefly shows its announcement before returning to compact playback. A pinned player remains open when paused.
- Click either side of the compact surface to expand the selected activity.
- New announcements briefly show a third, intermediate state: the compact wings plus a text row below the camera, then collapse automatically after four seconds. Click to open the activity, or use **Preview announcement** in the menu bar to try it again.
- Swipe left or right with two fingers over the expanded notch to switch activities. Dots below every activity (including music) show the available pages; the active page is a short line. You can also click an indicator or use the activity menu. Each swipe moves one page, with a directional transition that respects Reduce Motion.
- Use **Settings & Extensions…** in the menu bar (⌘,) to open the independent management window. Choose an extension directly from the sidebar to configure it. Enable/disable it from its page or the overview; use its action menu to open its activity, restart, disconnect, reveal or remove it. Access and package details are collapsible. Extensions can supply their own live setup panel through the SDK. General settings include hover expansion. You can also use the gear in the top-right wing of an expanded notch activity or its right-click menu. Closing this window keeps the notch running.
- Install a trusted built extension with **Install from Folder…**, review its name/version and declared connections, then confirm. Local packages are copied to `~/Library/Application Support/NotchNotch/Extensions`. Updates replace only the matching local package; removing it moves its folder to Trash. Included extensions can be disabled.
- The Marketplace page is reserved for discovery; no public catalog or remote installation service is connected yet. Local installation works now.
- Use the menu bar to reopen pending questions, restart extensions, or quit.

The shell uses an edge-attached silhouette with concave top shoulders, rounded lower corners, a soft shadow, and an interruptible spring morph. **The notch never scrolls: it grows to fit the entire content.** Its transparent canvas grows as needed and retains space during transitions; transparent areas pass clicks through to the app underneath. Reduce Motion removes the shape movement and blur. The visual reference is [Tuneful](https://tuneful.app/); extension content remains specific to NotchNotch.

During `pnpm dev`, changes to extension TypeScript/TSX are bundled automatically and restart only the changed extension within about a second. Extension state resets on reload. Changes to Swift require restarting `pnpm dev`.

## Build a local app

```sh
pnpm build
open dist/NotchNotch.app
```

The app contains its runner and extension bundles; Node.js is not needed to run the resulting app. The bundle is signed ad hoc for local development, not Developer ID signed or notarized for distribution. Open `Package.swift` in Xcode to work on the native targets.

## Verify

```sh
pnpm test
```

This checks TypeScript, builds the React bundles, runs Swift tests for presentation policy, JavaScriptCore and real loopback HTTP/WebSocket/stdio connections, then launches actual runner processes to verify runtime updates and prompts with a test-only fixture, plus music commands, Calendar state changes and the bundled native helpers. Tests that bind loopback listeners need local network access.

## Project layout

| Path | Purpose |
| --- | --- |
| `apps/macos` | App lifecycle, notch panel, menu bar, extension supervision |
| `native/NotchCore` | UI-independent activity and prompt presentation policy |
| `native/NotchProtocol` | Validated Codable wire models |
| `native/NotchRuntime` | JavaScriptCore bridge, timers, console, event delivery |
| `native/NotchExtensions` | Local package discovery, review validation and atomic installation |
| `native/NotchConnections` | Manifest-scoped local HTTP/WebSocket and JSONL process connections |
| `native/NotchRenderer` | SwiftUI components for the supported UI tree |
| `native/ExtensionRunner` | Headless extension executable |
| `packages/sdk` | Public React components |
| `packages/react-renderer` | Internal React reconciler adapter |
| `packages/runtime` | React mounting and event dispatch |
| `packages/protocol` | TypeScript wire models |
| `extensions` | Bundled Music and Calendar integrations |
| `tests/fixtures` | Runtime integration fixtures, excluded from the app |
| `schemas` | Manifest and snapshot contracts |

See [architecture](docs/architecture.md), [extension API](docs/extension-api.md), [local connections and external apps](docs/connections.md), and the [initial decisions](docs/decisions/0001-native-extension-platform.md).

## Preview boundaries

The runtime provides JavaScript, timers, console, React state/effects, and UI events. JavaScript has no DOM, CSS, Node API, direct filesystem access or general networking globals. `local-network` and `process` enable manifest-declared connections after session consent: local HTTP/WebSocket services and installed or bundled JSONL tools. Process permission runs trusted native code with the user's privileges. The management window imports explicitly trusted local folders; there is no public marketplace, publisher verification or OS-enforced helper sandbox. Album art uses a bounded native cache and approved artwork CDNs.

Process separation provides crash isolation; this preview does **not** implement an OS sandbox or resource quotas and must not load untrusted extensions. A production release still needs sandboxing, capability APIs, scheduling/background lifecycle, publisher verification for installation/updates, accessibility and multi-display/full-screen testing, and Developer ID signing/notarization. No private macOS APIs are used in this slice.


Music integration supports the installed Spotify and Apple Music desktop apps through their scripting interfaces. It does not capture system audio and does not use private MediaRemote APIs. The extension bundles its own native adapter and uses the same generic JSON-RPC/stdio SDK as external integrations. Playback controls respond immediately while that helper waits for confirmation; seeking holds its target through stale samples, and command failures restore the player state and display an error. The waveform indicates playback and is decorative, rather than measured audio levels. Apple Music must be installed to connect; denied access is reported in the app and can be granted in System Settings → Privacy & Security → Automation.

The Calendar extension uses public EventKit APIs through its own bundled helper. It reads accounts already added to macOS Calendar, including calendars synced from iCloud, Google or Exchange; it does not log into cloud services directly. Setup requests macOS Calendar access only when you click Connect. Calendar selection is stored locally by the helper. See [the Calendar adapter contract](extensions/calendar/README.md).
