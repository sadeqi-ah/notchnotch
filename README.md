# NotchNotch

A native macOS notch hub for music, calendar events, and extensible live activities.

**Developer preview.** Built with SwiftUI and AppKit, with extensions written in React and TypeScript.

## Features

- Music controls for Spotify and Apple Music.
- Upcoming calendar events with a live countdown and meeting links.
- An extension SDK and a settings window for managing integrations.

## Development

Requires macOS 14+, a Swift 6 toolchain, Node.js 22+, and pnpm.

```sh
pnpm install
pnpm dev
```

Connect Music and Calendar from **Settings & Extensions…** in the menu bar.

## Build and test

```sh
pnpm build
pnpm test
```

The app is built at `dist/NotchNotch.app`. Preview builds are locally signed and not notarized. Only install extensions you trust.

## Documentation

[Architecture](docs/architecture.md) · [Extension API](docs/extension-api.md) · [App connections](docs/connections.md)

## License

Copyright © 2026 AmirHossein Sadeghi. Licensed under [GNU GPL v3.0](LICENSE) (GPL-3.0-only).
