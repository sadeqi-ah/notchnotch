import { test } from "node:test";
import assert from "node:assert/strict";
import { build } from "esbuild";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { validateManifest } from "../scripts/manifest.mjs";

async function sdk(t, receive) {
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-sdk-"));
  const outfile = path.join(directory, "connections.mjs");
  await build({ entryPoints: ["packages/sdk/src/connections.ts"], outfile, bundle: true, platform: "node", format: "esm", logLevel: "silent" });
  globalThis.__notchnotchExtensionID = "dev.test.sdk";
  globalThis.__notchnotchSend = (json) => receive(JSON.parse(json));
  const module = await import(pathToFileURL(outfile).href);
  t.after(() => rm(directory, { recursive: true, force: true }));
  return module;
}
function response(command, result = null, error) {
  globalThis.__notchnotchConnectionDispatch({ protocolVersion: 1, type: "connectionResponse", requestID: command.requestID, result, error });
}
function event(connectionID, sessionID, message, kind = "message") {
  globalThis.__notchnotchConnectionDispatch({ protocolVersion: 1, type: "connectionEvent", connectionID, sessionID, event: kind, message });
}

test("HTTP responses correlate with concurrent requests even when replies arrive out of order", async (t) => {
  const commands = [];
  const { localHTTP } = await sdk(t, (command) => commands.push(command));
  const client = localHTTP("zeytun");
  const first = client.request("/pending");
  const second = client.request("/decisions", { method: "POST", body: '{"route":"direct"}' });
  response(commands[1], { status: 200, headers: {}, body: "second" });
  response(commands[0], { status: 200, headers: {}, body: "first" });
  assert.equal((await first).body, "first");
  assert.equal((await second).body, "second");
  assert.equal(commands[1].request.method, "POST");
});

test("RPC can receive a question and return a user decision over the same declared stream", async (t) => {
  const commands = [];
  const { ConnectionStream, JSONRPCClient } = await sdk(t, (command) => {
    commands.push(command); queueMicrotask(() => response(command));
  });
  const stream = new ConnectionStream("agent");
  const rpc = new JSONRPCClient(stream, { includeVersion: false });
  t.after(() => rpc.dispose());
  const serverRequests = [];
  rpc.onRequest((request) => serverRequests.push(request));
  await rpc.connect();
  const sessionID = commands[0].sessionID;
  const result = rpc.request("initialize", { clientInfo: { name: "test" } });
  await new Promise(setImmediate);
  const request = commands.find((command) => command.message?.method === "initialize");
  assert.equal(request.message.jsonrpc, undefined);
  event("agent", sessionID, { id: request.message.id, result: { ready: true } });
  assert.deepEqual(await result, { ready: true });
  event("agent", sessionID, { id: 42, method: "connection/decision", params: { host: "example.com" } });
  assert.equal(serverRequests[0].id, 42);
  await rpc.respond(42, { route: "direct" });
  assert.deepEqual(commands.at(-1).message, { id: 42, result: { route: "direct" } });
});

test("reopened streams discard old sessions and disconnect rejects outstanding RPC calls", async (t) => {
  const commands = [];
  const { ConnectionStream, JSONRPCClient } = await sdk(t, (command) => {
    commands.push(command); queueMicrotask(() => response(command));
  });
  const stream = new ConnectionStream("agent");
  const rpc = new JSONRPCClient(stream);
  t.after(() => rpc.dispose());
  const notifications = [];
  rpc.onNotification((message) => notifications.push(message));
  await rpc.connect();
  const oldSession = commands[0].sessionID;
  await rpc.disconnect();
  await rpc.connect();
  const newSession = commands.findLast((command) => command.operation === "open").sessionID;
  event("agent", oldSession, { method: "stale" });
  event("another-connection", newSession, { method: "foreign" });
  event("agent", newSession, { method: "fresh" });
  assert.deepEqual(notifications.map((message) => message.method), ["fresh"]);
  const pending = rpc.request("slow-method");
  const rejected = assert.rejects(pending, /Connection closed/);
  await new Promise(setImmediate);
  event("agent", newSession, null, "closed");
  await rejected;
});

test("denied connections surface errors and closing an opening stream cannot resurrect it", async (t) => {
  const commands = [];
  const { ConnectionStream } = await sdk(t, (command) => {
    commands.push(command);
    if (command.operation === "close") queueMicrotask(() => response(command));
  });
  const stream = new ConnectionStream("agent");
  const denied = stream.open();
  const rejected = assert.rejects(denied, /Denied/);
  response(commands[0], null, "Denied");
  await rejected;
  const opening = stream.open();
  const cancelled = assert.rejects(opening, /closed while opening/);
  const closing = stream.close();
  response(commands.at(-1));
  response(commands.findLast((command) => command.operation === "open"));
  await Promise.all([cancelled, closing]);
  await stream.dispose();
});

test("an RPC timeout can be recovered by closing the old helper session and reconnecting", async (t) => {
  const commands = [];
  const { ConnectionStream, JSONRPCClient } = await sdk(t, (command) => {
    commands.push(command); queueMicrotask(() => response(command));
  });
  const rpc = new JSONRPCClient(new ConnectionStream("player"));
  t.after(() => rpc.dispose());
  await assert.rejects(rpc.request("music/getState", undefined, 20), /RPC timed out: music\/getState/);
  const oldSession = commands.find((command) => command.operation === "open").sessionID;
  const oldRequest = commands.find((command) => command.message?.method === "music/getState");
  await rpc.disconnect();
  assert.equal(commands.at(-1).operation, "close");
  const retry = rpc.request("music/getState");
  await new Promise(setImmediate);
  const reopened = commands.findLast((command) => command.operation === "open");
  const next = commands.findLast((command) => command.message?.method === "music/getState");
  assert.notEqual(reopened.sessionID, oldSession);
  event("player", oldSession, { id: oldRequest.message.id, result: { stale: true } });
  event("player", reopened.sessionID, { id: next.message.id, result: { authorized: [], errors: {} } });
  assert.deepEqual(await retry, { authorized: [], errors: {} });
});

test("manifest validation rejects remote endpoints, undeclared powers and executable traversal", () => {
  const base = { id: "dev.test.plugin", name: "Test", version: "1", apiVersion: 1, entry: "bundle.js", permissions: ["local-network"] };
  validateManifest({ ...base, connections: { local: { transport: "http", endpoint: "http://127.0.0.1:4242" } } });
  for (const [key, value] of Object.entries({ name: "x".repeat(129), version: "v".repeat(65), icon: "x".repeat(129), description: "x".repeat(513) })) {
    assert.throws(() => validateManifest({ ...base, [key]: value }));
  }
  for (const endpoint of ["http://example.com:4242", "http://localhost:4242", "http://2130706433:4242", "http://127.0.0.1:4242/private"]) {
    assert.throws(() => validateManifest({ ...base, connections: { local: { transport: "http", endpoint } } }));
  }
  assert.throws(() => validateManifest({ ...base, permissions: [], connections: { local: { transport: "http", endpoint: "http://127.0.0.1:4242" } } }));
  assert.throws(() => validateManifest({ ...base, permissions: ["process"], connections: { tool: { transport: "stdio", executable: "./helpers/../../outside" } } }));
});
