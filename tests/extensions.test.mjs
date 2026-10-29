import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import path from "node:path";
import { root } from "../scripts/build-extensions.mjs";

function launch(name, id) {
  const child = spawn(path.join(root, ".build/debug/ExtensionRunner"), [path.join(root, "dist/extensions", name, "bundle.js"), id]);
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
    sendMedia(state) { child.stdin.write(JSON.stringify({ protocolVersion: 1, type: "media", state }) + "\n"); },
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
  const runner = launch("timer", "dev.notchnotch.timer");
  try {
    const initial = await runner.wait((message) => message.surfaces[0]?.phase === "paused");
    assert.equal(initial.protocolVersion, 1);
    assert.equal(initial.extensionID, "dev.notchnotch.timer");
    assert.equal(initial.surfaces[0].compact.trailing[0].props.text, "05:00");
    assert.deepEqual(initial.surfaces[0].peek, {
      id: "ready", text: "Focus timer • Ready when you are", duration: 4,
    });
    runner.send(action(initial.surfaces[0], "Start focus"));
    const running = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    const ticked = await runner.wait((message) => message.revision > running.revision && message.surfaces[0]?.compact.trailing[0].props.text !== "05:00");
    // Live progress retains the event id, so the host's deadline stays fixed.
    assert.deepEqual(ticked.surfaces[0].peek, initial.surfaces[0].peek);
    runner.send(action(ticked.surfaces[0], "Pause"));
    const paused = await runner.wait((message) => message.revision > ticked.revision && message.surfaces[0]?.phase === "paused");
    runner.send(action(paused.surfaces[0], "Reset"));
    const reset = await runner.wait((message) => message.revision > paused.revision && message.surfaces[0]?.compact.trailing[0].props.text === "05:00");
    assert.equal(reset.surfaces[0].phase, "paused");
  } finally { await runner.stop(); }
});

test("An expanded-only prompt accepts text and resolves without removing the activity", async () => {
  const runner = launch("prompt-demo", "dev.notchnotch.prompt-demo");
  try {
    const initial = await runner.wait((message) => message.surfaces.length === 1);
    runner.send(action(initial.surfaces[0], "Try a prompt"));
    const question = await runner.wait((message) => message.surfaces.some((surface) => surface.kind === "prompt"));
    const prompt = question.surfaces.find((surface) => surface.kind === "prompt");
    assert.equal(prompt.initialView, "expanded");
    assert.equal(prompt.compact, undefined);
    const input = nodes(prompt.expanded).find((node) => node.type === "textField");
    runner.send(input.props.action, "Building NotchNotch");
    const typed = await runner.wait((message) => message.revision > question.revision && message.surfaces.some((surface) =>
      nodes(surface.expanded).some((node) => node.type === "textField" && node.props.text === "Building NotchNotch")));
    runner.send(action(typed.surfaces.find((surface) => surface.kind === "prompt"), "Save name"));
    const resolved = await runner.wait((message) => message.revision > typed.revision && message.surfaces.length === 1);
    assert.ok(nodes(resolved.surfaces[0].expanded).some((node) => node.props.text === "Session named “Building NotchNotch”."));
    assert.equal(resolved.surfaces[0].kind, "activity");
  } finally { await runner.stop(); }
});

test("Unknown action identifiers do not execute extension callbacks", async () => {
  const runner = launch("timer", "dev.notchnotch.timer");
  try {
    const initial = await runner.wait((message) => message.surfaces.length === 1);
    runner.send("not-an-action");
    runner.send(action(initial.surfaces[0], "Start focus"));
    const running = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    assert.equal(running.revision, initial.revision + 1);
  } finally { await runner.stop(); }
});


test("Music receives real wire updates, keeps event ids stable, and sends playback commands", async () => {
  const runner = launch("music", "dev.notchnotch.music");
  const state = { id: "spotify:track:example", eventID: "playback-1", player: "com.spotify.client",
    title: "Thisavros Mou", artist: "Katerina", album: "Thisavros Mou", duration: 204,
    position: 12, isPlaying: true, volume: 0.6, shuffle: false, repeating: false,
    updatedAt: Date.now() / 1000 };
  try {
    await runner.wait((message) => message.surfaces.length === 0);
    runner.sendMedia(state);
    const playing = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    const surface = playing.surfaces[0];
    assert.equal(surface.idlePreview, true);
    assert.equal(surface.compact.leading[0].type, "artwork");
    assert.equal(surface.compact.trailing[0].type, "waveform");
    assert.equal(surface.peek.id, state.eventID);
    assert.equal(surface.peek.text, "Katerina • Thisavros Mou");
    const player = nodes(surface.expanded).find((node) => node.type === "player");
    assert.equal(player.props.media.title, state.title);
    runner.send(player.props.action, JSON.stringify({ command: "seek", value: 0.5 }));
    const command = await runner.waitMessage((message) => message.type === "mediaCommand");
    assert.equal(command.extensionID, "dev.notchnotch.music");
    assert.deepEqual(command.request, { command: "seek", value: 0.5 });
    runner.sendMedia({ ...state, position: 13 });
    const tick = await runner.wait((message) => message.revision > playing.revision);
    assert.equal(tick.surfaces[0].peek.id, state.eventID);
    runner.sendMedia({ ...state, isPlaying: false });
    const paused = await runner.wait((message) => message.surfaces[0]?.phase === "paused");
    assert.equal(paused.surfaces[0].compact.trailing[0].props.name, "pause.fill");
    assert.equal(nodes(paused.surfaces[0].expanded).find((node) => node.type === "player").props.media.isPlaying, false);
    // Album artwork can be larger than an ordinary 8 KiB UI event.
    const artwork = "data:image/jpeg;base64," + "a".repeat(24000);
    runner.sendMedia({ ...state, artwork, eventID: "playback-2" });
    const art = await runner.wait((message) => message.surfaces[0]?.peek?.id === "playback-2");
    assert.equal(art.surfaces[0].compact.leading[0].props.source, artwork);
    runner.sendMedia(null);
    await runner.wait((message) => message.revision > art.revision && message.surfaces.length === 0);
  } finally { await runner.stop(); }
});
