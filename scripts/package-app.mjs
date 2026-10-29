import { mkdir, cp, writeFile, chmod } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { root } from "./build-extensions.mjs";

export async function packageApp() {
  const app = path.join(root, "dist/NotchNotch.app");
  const contents = path.join(app, "Contents");
  await mkdir(path.join(contents, "MacOS"), { recursive: true });
  await mkdir(path.join(contents, "Helpers"), { recursive: true });
  await mkdir(path.join(contents, "Resources"), { recursive: true });
  await cp(path.join(root, ".build/debug/NotchNotch"), path.join(contents, "MacOS/NotchNotch"));
  await cp(path.join(root, ".build/debug/ExtensionRunner"), path.join(contents, "Helpers/ExtensionRunner"));
  await chmod(path.join(contents, "MacOS/NotchNotch"), 0o755);
  await chmod(path.join(contents, "Helpers/ExtensionRunner"), 0o755);
  await cp(path.join(root, "dist/extensions"), path.join(contents, "Resources/extensions"), { recursive: true });
  await writeFile(path.join(contents, "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.notchnotch.app</string>
<key>CFBundleName</key><string>NotchNotch</string>
<key>CFBundleDisplayName</key><string>NotchNotch</string>
<key>CFBundleExecutable</key><string>NotchNotch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Show the current song and control playback in Spotify and Apple Music from your notch.</string>
</dict></plist>
`);
  for (const target of [path.join(contents, "Helpers/ExtensionRunner"), app]) {
    const result = spawnSync("codesign", ["--force", "--sign", "-", target], { stdio: "inherit" });
    if (result.status !== 0) throw new Error("Local ad-hoc signing failed");
  }
  console.log(`App ready: ${app}`);
  return app;
}
if (process.argv[1] === new URL(import.meta.url).pathname) await packageApp();
