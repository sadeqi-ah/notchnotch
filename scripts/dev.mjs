import { spawn } from "node:child_process";
import path from "node:path";
import { buildExtensions, root } from "./build-extensions.mjs";
import { packageApp } from "./package-app.mjs";

const watchers = await buildExtensions({ watch: true });
const build = spawn("swift", ["build", "--cache-path", ".build/cache"], { cwd: root, stdio: "inherit" });
const status = await new Promise((resolve, reject) => { build.on("exit", resolve); build.on("error", reject); });
if (status !== 0) {
  await Promise.all(watchers.map((watcher) => watcher.dispose()));
  process.exit(status ?? 1);
}
// Wait for initial watch builds before packaging resources.
await Promise.all(watchers.map((watcher) => watcher.rebuild()));
const app = await packageApp();
const child = spawn(path.join(app, "Contents/MacOS/NotchNotch"), [], {
  cwd: root, stdio: "inherit",
  env: { ...process.env, NOTCHNOTCH_DEV: "1",
    NOTCHNOTCH_EXTENSIONS: path.join(root, "dist/extensions"),
    NOTCHNOTCH_RUNNER: path.join(app, "Contents/Helpers/ExtensionRunner") },
});
let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  child.kill("SIGTERM");
  await Promise.all(watchers.map((watcher) => watcher.dispose()));
}
child.on("error", async (error) => { console.error(error.message); await close(); process.exitCode = 1; });
child.on("exit", async () => { await close(); });
process.on("SIGINT", close);
process.on("SIGTERM", close);
console.log("NotchNotch is running. Edit an extension to reload it. Press Ctrl+C to stop.");
