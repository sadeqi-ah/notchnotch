import { after, before, test } from "node:test";
import { build } from "esbuild";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import path from "node:path";
import { root } from "../scripts/build-extensions.mjs";

// Exercise the runtime without shipping test activities as installed extensions.
let fixtureDirectory;
before(async () => {
  fixtureDirectory = await mkdtemp(path.join(tmpdir(), "notchnotch-runtime-"));
  await build({
    absWorkingDir: root,
    entryPoints: ["tests/fixtures/runtime.tsx"],
    outfile: path.join(fixtureDirectory, "bundle.js"),
    bundle: true, format: "iife", platform: "neutral", target: "es2022",
    mainFields: ["module", "main"], conditions: ["default"], jsx: "automatic",
    define: { "process.env.NODE_ENV": '"production"' },
  });
});
after(async () => {
  if (fixtureDirectory) await rm(fixtureDirectory, { recursive: true, force: true });
});
function launchFixture() {
  return launchProcess(path.join(root, ".build/debug/ExtensionRunner"),
    [path.join(fixtureDirectory, "bundle.js"), "test.runtime"]);
}

function launch(name, id) {
  return launchProcess(path.join(root, ".build/debug/ExtensionRunner"), [path.join(root, "dist/extensions", name, "bundle.js"), id]);
}
function launchProcess(executable, args) {
  const child = spawn(executable, args);
  const messages = [];
  const waiters = new Set();
  let stderr = "";
  let exited = false;
  createInterface({ input: child.stdout }).on("line", (line) => {
    const message = JSON.parse(line);
    messages.push(message);
    for (const notify of waiters) notify();
  });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.on("exit", () => { exited = true; for (const notify of waiters) notify(); });
  child.on("error", (error) => { stderr += error.message; exited = true; for (const notify of waiters) notify(); });
  return {
    child, messages,
    send(action, value) { child.stdin.write(JSON.stringify({ protocolVersion: 1, type: "event", action, value }) + "\n"); },
    message(message) { child.stdin.write(JSON.stringify({ protocolVersion: 1, ...message }) + "\n"); },
    wait(predicate) { return this.waitMessage((message) => message.type === "snapshot" && predicate(message)); },
    waitMessage(predicate) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { waiters.delete(check); reject(new Error(`Runner timeout: ${stderr}; ${JSON.stringify(messages.slice(-2))}`)); }, 6000);
        function check() {
          const error = messages.find((message) => message.type === "error");
          const found = messages.find(predicate);
          if (error || found || exited) {
            clearTimeout(timer); waiters.delete(check);
            if (error || !found) reject(new Error(error?.message ?? `Runner exited: ${stderr}`));
            else resolve(found);
          }
        }
        waiters.add(check); check();
      });
    },
    async stop() {
      if (exited) return;
      child.stdin.end();
      await new Promise((resolve) => child.on("exit", resolve));
    },
  };
}
function nodes(node) { return [node, ...node.children.flatMap(nodes)]; }
function action(surface, title) {
  const button = nodes(surface.expanded).find((node) => node.type === "button" && node.props.text === title);
  assert.ok(button?.props.action, `Missing action: ${title}`);
  return button.props.action;
}

test("React timer runs inside JavaScriptCore and round-trips actions across the process boundary", async () => {
  const runner = launchFixture();
  try {
    const initial = await runner.wait((message) => message.surfaces[0]?.phase === "paused");
    assert.equal(initial.protocolVersion, 1);
    assert.equal(initial.extensionID, "test.runtime");
    assert.equal(initial.surfaces[0].compact.trailing[0].props.text, "5");
    assert.deepEqual(initial.surfaces[0].peek, {
      id: "ready", text: "Runtime ready", duration: 4,
    });
    runner.send(action(initial.surfaces[0], "Start"));
    const running = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    const ticked = await runner.wait((message) => message.revision > running.revision && message.surfaces[0]?.compact.trailing[0].props.text !== "5");
    // Live progress retains the event id, so the host's deadline stays fixed.
    assert.deepEqual(ticked.surfaces[0].peek, initial.surfaces[0].peek);
    runner.send(action(ticked.surfaces[0], "Pause"));
    const paused = await runner.wait((message) => message.revision > ticked.revision && message.surfaces[0]?.phase === "paused");
    runner.send(action(paused.surfaces[0], "Reset"));
    const reset = await runner.wait((message) => message.revision > paused.revision && message.surfaces[0]?.compact.trailing[0].props.text === "5");
    assert.equal(reset.surfaces[0].phase, "paused");
  } finally { await runner.stop(); }
});

test("An expanded-only prompt accepts text and resolves without removing the activity", async () => {
  const runner = launchFixture();
  try {
    const initial = await runner.wait((message) => message.surfaces.length === 1);
    runner.send(action(initial.surfaces[0], "Ask"));
    const question = await runner.wait((message) => message.surfaces.some((surface) => surface.kind === "prompt"));
    const prompt = question.surfaces.find((surface) => surface.kind === "prompt");
    assert.equal(prompt.initialView, "expanded");
    assert.equal(prompt.compact, undefined);
    const input = nodes(prompt.expanded).find((node) => node.type === "textField");
    runner.send(input.props.action, "Building NotchNotch");
    const typed = await runner.wait((message) => message.revision > question.revision && message.surfaces.some((surface) =>
      nodes(surface.expanded).some((node) => node.type === "textField" && node.props.text === "Building NotchNotch")));
    runner.send(action(typed.surfaces.find((surface) => surface.kind === "prompt"), "Save"));
    const resolved = await runner.wait((message) => message.revision > typed.revision && message.surfaces.length === 1);
    assert.ok(nodes(resolved.surfaces[0].expanded).some((node) => node.props.text === "Building NotchNotch"));
    assert.equal(resolved.surfaces[0].kind, "activity");
  } finally { await runner.stop(); }
});

test("Unknown action identifiers do not execute extension callbacks", async () => {
  const runner = launchFixture();
  try {
    const initial = await runner.wait((message) => message.surfaces.length === 1);
    runner.send("not-an-action");
    runner.send(action(initial.surfaces[0], "Start"));
    const running = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    assert.equal(running.revision, initial.revision + 1);
  } finally { await runner.stop(); }
});


test("Music connects through the generic SDK, receives state, and sends playback RPCs", async () => {
  const runner = launch("music", "dev.notchnotch.music");
  const state = { id: "spotify:track:example", eventID: "playback-1", player: "com.spotify.client", playerName: "Spotify",
    title: "Thisavros Mou", artist: "Katerina", album: "Thisavros Mou", duration: 204,
    position: 12, isPlaying: true, volume: 0.6, shuffle: false, repeating: false,
    updatedAt: Date.now() / 1000 };
  const status = (state) => ({ state, authorized: ["com.spotify.client"], errors: {} });
  function acknowledge(command) {
    runner.message({ type: "connectionResponse", requestID: command.requestID, result: null });
  }
  function incoming(sessionID, message) {
    runner.message({ type: "connectionEvent", connectionID: "player", sessionID, event: "message", message });
  }
  try {
    const initial = await runner.wait((message) => !!message.settings);
    assert.deepEqual(initial.surfaces, []);
    assert.ok(nodes(initial.settings).some((node) => node.props.text === "Connect Spotify"));
    assert.equal(runner.messages.some((message) => message.type === "connectionCommand"), false);
    runner.send(action({ expanded: initial.settings }, "Connect Spotify"));
    const open = await runner.waitMessage((message) => message.type === "connectionCommand" && message.operation === "open");
    assert.equal(open.connectionID, "player");
    acknowledge(open);
    const get = await runner.waitMessage((message) => message.message?.method === "music/getState");
    acknowledge(get);
    incoming(open.sessionID, { jsonrpc: "2.0", id: get.message.id, result: status(state) });
    const connect = await runner.waitMessage((message) => message.message?.method === "music/connect");
    assert.deepEqual(connect.message.params, { player: "com.spotify.client" });
    acknowledge(connect);
    incoming(open.sessionID, { jsonrpc: "2.0", id: connect.message.id, result: status(state) });
    const playing = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    const surface = playing.surfaces[0];
    assert.equal(surface.idlePreview, true);
    assert.equal(surface.compact.leading[0].type, "artwork");
    assert.equal(surface.compact.trailing[0].type, "waveform");
    assert.equal(surface.peek.id, state.eventID);
    assert.equal(surface.peek.text, "Katerina • Thisavros Mou");
    const player = nodes(surface.expanded).find((node) => node.type === "player");
    assert.equal(player.props.media.title, state.title);
    assert.equal(nodes(surface.expanded).some((node) => /Connect|Players/.test(node.props.text ?? "")), false);
    assert.ok(nodes(playing.settings).some((node) => node.props.text === "Connect Apple Music"));
    runner.send(player.props.action, JSON.stringify({ command: "seek", value: 0.5 }));
    const command = await runner.waitMessage((message) => message.message?.method === "music/command");
    assert.equal(command.type, "connectionCommand");
    assert.equal(command.extensionID, "dev.notchnotch.music");
    assert.deepEqual(command.message.params, { command: "seek", value: 0.5 });
    acknowledge(command);
    incoming(open.sessionID, { jsonrpc: "2.0", id: command.message.id, result: null });
    incoming(open.sessionID, { jsonrpc: "2.0", method: "music/state", params: status({ ...state, position: 13 }) });
    const tick = await runner.wait((message) => message.revision > playing.revision &&
      nodes(message.surfaces[0].expanded).some((node) => node.props.media?.position === 13));
    assert.equal(tick.surfaces[0].peek.id, state.eventID);
    incoming(open.sessionID, { method: "music/state", params: status({ ...state, isPlaying: false }) });
    const paused = await runner.wait((message) => message.revision > tick.revision && message.surfaces[0]?.phase === "paused");
    assert.equal(paused.surfaces[0].compact.trailing[0].props.name, "pause.fill");
    const artwork = "data:image/jpeg;base64," + "a".repeat(24000);
    incoming(open.sessionID, { method: "music/state", params: status({ ...state, artwork, eventID: "playback-2" }) });
    const art = await runner.wait((message) => message.surfaces[0]?.peek?.id === "playback-2");
    assert.equal(art.surfaces[0].compact.leading[0].props.source, artwork);
    incoming(open.sessionID, { method: "music/state", params: { ...status(state), commandError: "Player unavailable" } });
    await runner.wait((message) => message.revision > art.revision &&
      nodes(message.surfaces[0].expanded).some((node) => node.props.text === "Player unavailable"));
    runner.message({ type: "connectionEvent", connectionID: "player", sessionID: open.sessionID, event: "closed" });
    await runner.wait((message) => message.revision > art.revision &&
      message.surfaces.length === 0 && nodes(message.settings).some((node) => node.props.text === "Connect Spotify"));
    assert.equal(runner.messages.filter((message) => message.operation === "open").length, 1);
    assert.equal(runner.messages.some((message) => message.type === "mediaCommand"), false);
  } finally { await runner.stop(); }
});

test("The packaged music helper speaks bounded JSON-RPC and rejects unsupported actions", async () => {
  const runner = launchProcess(path.join(root, "dist/extensions/music/helpers/MusicAdapter.app/Contents/MacOS/MusicAdapter"), []);
  function request(id, method, params) {
    runner.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  }
  try {
    request("state", "music/getState");
    const initial = await runner.waitMessage((message) => message.id === "state");
    assert.equal(initial.jsonrpc, "2.0");
    assert.ok(Array.isArray(initial.result.authorized));
    assert.equal(typeof initial.result.errors, "object");
    request("unknown", "arbitraryScript", { script: "do something" });
    const unknown = await runner.waitMessage((message) => message.id === "unknown");
    assert.equal(unknown.error.code, -32601);
    request("player", "music/connect", { player: "arbitrary.application" });
    assert.equal((await runner.waitMessage((message) => message.id === "player")).error.code, -32602);
    request("command", "music/command", { command: "runScript" });
    assert.equal((await runner.waitMessage((message) => message.id === "command")).error.code, -32602);
    request("final", "music/getState");
    await runner.waitMessage((message) => message.id === "final");
    assert.equal(runner.messages.filter((message) => message.id === "unknown").length, 1);
  } finally { await runner.stop(); }
});
