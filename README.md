# NotchNotch

A shared space in the Mac notch for live activities and quick questions.

This is a working developer preview: a native AppKit/SwiftUI host, a separate JavaScriptCore process for each extension, a React renderer, and three bundled extensions. It is intended for local development with trusted code.

## Run

Requires macOS 14+, Xcode 16+ (or a compatible Swift 6 toolchain), Node.js 22+, and pnpm 11.5.3.

```sh
pnpm install
pnpm dev
```

The app appears at the top of the built-in notched display, or as a small pill on the main display when no notch is available. It has a menu bar icon and no Dock icon.

- When nothing is active, the app is completely hidden behind the physical notch. Installed or paused extensions do not keep it visible.
- A short hover reveals the idle notch, or slightly enlarges an active notch and adds a soft shadow. Dwell for 850 ms to open its full view; leaving closes a hover preview after 180 ms. Click to pin it open.
- Open the **Music** activity and click **Connect music** to start its bundled helper after session consent. Use **Connect Spotify** or **Connect Apple Music** inside that activity to request macOS Automation access. The music extension shows real album artwork, a playback waveform, title/artist, seek bar, shuffle, previous/play/next, and repeat controls.
- Pausing hides an unpinned music activity; a new song briefly shows its announcement before returning to compact playback. A pinned player remains open when paused.
- Click either side of the compact surface to expand the selected activity.
- New announcements briefly show a third, intermediate state: the compact wings plus a text row below the camera, then collapse automatically after four seconds. Click to open the activity, or use **Preview announcement** in the menu bar to try it again.
- Open **Show activities** and use the activity menu to start, pause, and reset the five-minute timer. The timer and quick-question launcher start paused so the initial notch stays idle.
- Swipe left or right with two fingers over the expanded notch to switch activities. Dots below every activity (including music) show the available pages; the active page is a short line. You can also click an indicator or use the activity menu. Each swipe moves one page, with a directional transition that respects Reduce Motion.
- Switch to **Quick question**, then click **Try a prompt**.
- The small question icon opens the expanded-only prompt. The current activity stays in place until you choose to switch.
- Type a session name and save, or explicitly skip the question.
- Closing the panel or pressing Escape leaves an unanswered prompt pending.
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

This checks TypeScript, builds the React bundles, runs Swift tests for presentation policy, JavaScriptCore and real loopback HTTP/WebSocket/stdio connections, then launches actual runner processes to verify timer updates, music commands, prompts and the bundled music helper. Tests that bind loopback listeners need local network access.

## Project layout

| Path | Purpose |
| --- | --- |
| `apps/macos` | App lifecycle, notch panel, menu bar, extension supervision |
| `native/NotchCore` | UI-independent activity and prompt presentation policy |
| `native/NotchProtocol` | Validated Codable wire models |
| `native/NotchRuntime` | JavaScriptCore bridge, timers, console, event delivery |
| `native/NotchConnections` | Manifest-scoped local HTTP/WebSocket and JSONL process connections |
| `native/NotchRenderer` | SwiftUI components for the supported UI tree |
| `native/ExtensionRunner` | Headless extension executable |
| `packages/sdk` | Public React components |
| `packages/react-renderer` | Internal React reconciler adapter |
| `packages/runtime` | React mounting and event dispatch |
| `packages/protocol` | TypeScript wire models |
| `extensions` | Music, timer and prompt examples |
| `schemas` | Manifest and snapshot contracts |

See [architecture](docs/architecture.md), [extension API](docs/extension-api.md), [local connections and external apps](docs/connections.md), and the [initial decisions](docs/decisions/0001-native-extension-platform.md).

## Preview boundaries

The runtime provides JavaScript, timers, console, React state/effects, and UI events. JavaScript has no DOM, CSS, Node API, direct filesystem access or general networking globals. `local-network` and `process` enable manifest-declared connections after session consent: local HTTP/WebSocket services and installed or bundled JSONL tools. Process permission runs trusted native code with the user's privileges. There is no third-party extension installer or OS-enforced helper sandbox. Album art uses a bounded native cache and approved artwork CDNs.

Process separation provides crash isolation; this preview does **not** implement an OS sandbox or resource quotas and must not load untrusted extensions. A production release still needs sandboxing, capability APIs, scheduling/background lifecycle, extension installation/update verification, accessibility and multi-display/full-screen testing, and Developer ID signing/notarization. No private macOS APIs are used in this slice.


Music integration supports the installed Spotify and Apple Music desktop apps through their scripting interfaces. It does not capture system audio and does not use private MediaRemote APIs. The extension bundles its own native adapter and uses the same generic JSON-RPC/stdio SDK as external integrations. Playback controls respond immediately while that helper waits for confirmation; seeking holds its target through stale samples, and command failures restore the player state and display an error. The waveform indicates playback and is decorative, rather than measured audio levels. Apple Music must be installed to connect; denied access is reported in the app and can be granted in System Settings → Privacy & Security → Automation.
