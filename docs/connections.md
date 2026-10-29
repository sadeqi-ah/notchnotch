# Local connections and external applications

Extensions can talk to an app you own or integrate an installed third-party tool without adding application-specific code to NotchNotch. The SDK provides local HTTP, WebSocket JSON messages, JSONL subprocesses, and a bidirectional JSON-RPC client. The native host owns transport and consent; extensions own the application protocol and UI.

## Choose a transport

| Situation | Transport |
| --- | --- |
| Your app already exposes a local request/response API | `http` |
| Your app emits events and accepts decisions in real time | `websocket` |
| An external app offers a CLI or protocol server | `stdio` |
| An integration needs custom native code | Bundle an executable helper and use `stdio` |

WebSockets and subprocesses remain open rather than polling or starting a process for each event. No Node runtime or new dependency is added to the host. Each extension has up to eight declared connections and its own subprocesses and request registry.

## Declare a destination

Add named connections to `notchnotch.json`. HTTP connections declare an origin; WebSockets declare the complete endpoint, including a fixed path if needed. Use literal `127.0.0.1` or `[::1]` and an explicit port. DNS names, remote destinations, URL credentials, query strings and fragments are rejected. HTTP paths are supplied per request; redirects are returned to the extension rather than followed. System proxy settings, cookies and HTTP caches are not used.

```json
{
  "id": "dev.example.zeytun",
  "name": "Zeytun",
  "version": "0.1.0",
  "apiVersion": 1,
  "entry": "bundle.js",
  "permissions": ["local-network"],
  "connections": {
    "api": { "transport": "http", "endpoint": "http://127.0.0.1:4277" },
    "events": { "transport": "websocket", "endpoint": "ws://127.0.0.1:4277/events" }
  }
}
```

The first operation prompts for session access to the concrete destination. A manifest declaration alone grants no access. A denial is remembered until the extension is reloaded. **Disconnect extension connections** in the menu bar closes all transports, cancels pending operations and clears grants. Reloading a manifest also replaces its broker and grants.

## Zeytun-style connection decisions

The routes and event shapes here are an example contract for Zeytun to implement, not an existing Zeytun API. Keep a request id and deadline in the owning app; a closed notch must not silently approve or reject a connection.

```tsx
import { useEffect, useState } from "react";
import { Button, ConnectionStream, Prompt, Settings, Text, localHTTP } from "@notchnotch/sdk";

const api = localHTTP("api");
const events = new ConnectionStream("events");
type Pending = { id: string; host: string };

function ConnectionQuestions() {
  const [pending, setPending] = useState<Pending[]>([]);
  const [error, setError] = useState("");

  useEffect(() => events.subscribe((event) => {
    if (event.event === "closed") { setError(event.error ?? "Disconnected"); return; }
    const message = event.message as { type?: string; connection?: Pending; id?: string };
    if (message.type === "connection/pending" && message.connection) {
      const connection = message.connection;
      setPending((current) => current.some((item) => item.id === connection.id) ? current : [...current, connection]);
    }
    if (message.type === "connection/resolved") setPending((current) => current.filter((item) => item.id !== message.id));
  }), []);

  async function decide(id: string, route: string) {
    try {
      const response = await api.request("/connections/decision", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id, route }),
      });
      if (response.status !== 200) throw new Error(`Decision failed: ${response.status}`);
      setPending((current) => current.filter((item) => item.id !== id));
    } catch (error) { setError(String(error)); }
  }

  return <>
    <Settings>
      <Button title="Connect Zeytun" onPress={() => { void events.open().catch((error) => setError(String(error))); }} />
      {error ? <Text tone="warning">{error.slice(0, 4096)}</Text> : null}
    </Settings>
    {pending.slice(0, 8).map((connection) => <Prompt key={connection.id} id={connection.id} title="New connection">
      <Prompt.Expanded>
        <Text>{connection.host}</Text>
        <Button title="Reject" onPress={() => { void decide(connection.id, "reject"); }} />
        <Button title="Direct" onPress={() => { void decide(connection.id, "direct"); }} />
        <Button title="Work proxy" onPress={() => { void decide(connection.id, "proxy:work"); }} />
      </Prompt.Expanded>
    </Prompt>)}
  </>;
}
```

Render this component as the extension root. Validate service data before rendering it. Handle duplicate events, service reconnects, expired requests and decision failures; remove a question only after the owning app confirms a decision. Use an initial HTTP query to recover pending questions after reconnecting. `ConnectionStream` does not reconnect automatically, so an offline service never causes repeated consent dialogs or silently replays decisions.

`localHTTP(id).request(path, options)` returns `{ status, headers, body }`. Bodies are UTF-8 text; parse JSON explicitly. The default method is `GET`. `timeoutMs` is 1–30,000 (default 15,000). Tokens, if your local service uses them, can be sent in declared-origin request headers or in your WebSocket application handshake. There is no generic secret store in this preview; do not put secrets in a distributable manifest.

## Third-party CLIs and bundled adapters

An installed app does not have to belong to the extension developer. It does need a usable interface: for example a documented CLI, local API, Apple events or another integration point. A helper can adapt that interface to JSONL. Apps with no exposed integration interface still need an app-specific adapter; the SDK cannot manufacture access to their internal state.

```json
{
  "permissions": ["process"],
  "connections": {
    "adapter": {
      "transport": "stdio",
      "executable": "./helpers/my-adapter",
      "arguments": []
    }
  }
}
```

`executable` accepts a tool name, an absolute path, or a bundle-relative `./` path with no `..` components. Named tools are resolved in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin` and `~/.local/bin`. The permission dialog displays the resolved executable and fixed arguments. Bundled executables are resolved through symlinks and must remain inside the extension directory. Build tools copy the extension's `helpers/` directory into its bundle; mark entry scripts executable and include an appropriate shebang. An optional extension-local `build.mjs` can export `async build({ root, source, destination })` to compile/package helpers before the JavaScript bundle. This is trusted development-time code, never a host API. The Music example uses it to compile and sign its adapter. Restart development after changing helper resources or Swift sources. No shell interpolation occurs. Arguments cannot be changed by extension JavaScript.

Native tools receive a small environment (`HOME`, a fixed `PATH`, `LANG`) and can use their existing login/config files. Shell API keys and other environment variables are not inherited. Bundled helpers start in the extension directory; installed tools start in the user's home directory. OS privacy or Automation permissions, where needed by an adapter, still apply.

**Process permission is a trust decision.** Helpers are ordinary processes running as the user, with filesystem and network access; they are not OS-sandboxed. Keep the JavaScript UI constrained, and only grant process access to trusted code. Closing a stream or unloading its extension terminates its immediate child; a helper is responsible for cleaning up any descendants it creates. Full untrusted-extension distribution still needs sandboxing, installation verification and resource enforcement.

Subprocess stdout must contain exactly one JSON value per line (JSONL); use stderr for logs. WebSocket frames must also contain a JSON value. Messages and HTTP bodies are limited to 64 KiB, enclosing protocol messages to 256 KiB, pending connection operations to 32, and stream delivery to 256 messages per second. Oversized/invalid stream data closes that connection. Each stream has a session id so callbacks from an older connection cannot reach a reopened one.

## Bidirectional JSON-RPC

```ts
import { ConnectionStream, JSONRPCClient } from "@notchnotch/sdk";

const stream = new ConnectionStream("adapter");
const rpc = new JSONRPCClient(stream);
const stopQuestions = rpc.onRequest((request) => {
  // Store the request in React state and show a Prompt.
  // On explicit user choice: rpc.respond(request.id, decision).
});
const stopEvents = rpc.onNotification(({ method, params }) => {
  // Update your activity from streamed progress or messages.
});
await rpc.connect();
await rpc.request("initialize", { clientInfo: { name: "notchnotch", version: "0.1.0" } });
```

The client correlates concurrent requests, supports string/number server request ids, propagates remote errors, times out requests and rejects pending RPCs when disconnected. `includeVersion` defaults to true; set it to false only when an adapter requires unversioned envelopes. Unknown server requests receive a method-not-found response when no request handler is registered. With a handler installed, the extension must explicitly `respond` or `reject` each supported request. Notifications, questions and approvals remain application-level concepts.

Call `stream.subscribe` before `stream.open`, or use `JSONRPCClient` which installs its listener at construction. Use `rpc.disconnect()` for a reconnectable client and `rpc.dispose()` when permanently releasing it. Neither method auto-approves unanswered server requests. HTTP operations use a 35-second client timeout; opening a stream allows two minutes for the consent dialog. If you abandon a question, explicitly cancel it through the application's protocol before disconnecting when the application supports that.

## Included Music extension

Music also uses the generic stdio/JSON-RPC path. Open **Settings & Extensions… → Extensions → Music → Setup** and choose **Connect Spotify** or **Connect Apple Music**, then grant session access to the bundled adapter. It reads existing Automation grants silently; **Connect Spotify** / **Connect Apple Music** request access explicitly. Track discovery, playback commands, errors and OS permissions belong to `extensions/music/helper-src`. The host retains reusable player UI only. Disconnect/reload terminates the helper; its settings panel offers an explicit reconnect instead of reopening it or replaying a command. See [the adapter contract](../extensions/music/README.md).
