# 0001 — Native host with React extension descriptions

Status: accepted for the first local developer preview.

The product needs a predictable macOS notch surface and an approachable extension API. Use AppKit for window/focus behavior, SwiftUI for native content, and UI-independent Swift state for activity/prompt presentation. Use React and TypeScript as the extension authoring API with a dedicated renderer that emits a versioned UI tree.

Run bundled JavaScript in a separate JavaScriptCore helper per extension. This avoids requiring Node on end-user machines and keeps extension logic out of the app's UI process. It requires explicitly implementing runtime APIs and limits npm compatibility to code that can run in the supplied environment.

Use Swift Package Manager initially rather than committing a generated Xcode project. One root package declares native libraries, app/runner executables, and tests; it can be opened directly in Xcode. A script packages executables and resources into an ad-hoc-signed local `.app`. A distribution-oriented Xcode/signing setup can be added when sandboxing and release requirements are settled.

Use complete snapshots initially. Their small, bounded trees are easier to validate and recover after reload than a patch stream. Preserve stable node IDs. Add patches only when measurements justify them.

Keep extensions local and trusted in this preview. Third-party installation, capability permissions, OS sandboxing, quotas, public npm distribution, and notarized releases are follow-up work, not implied by the existence of a separate process.
