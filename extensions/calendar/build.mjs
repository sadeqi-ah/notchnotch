import { spawnSync } from "node:child_process";
import { mkdir, copyFile, writeFile, chmod } from "node:fs/promises";
import path from "node:path";

export async function build({ root, destination }) {
  const result = spawnSync("swift", ["build", "--disable-sandbox", "--cache-path", ".build/cache", "--product", "CalendarAdapter"], {
    cwd: root, stdio: "inherit", env: { ...process.env,
      CLANG_MODULE_CACHE_PATH: path.join(root, ".build/cache/clang"),
      SWIFTPM_MODULECACHE_OVERRIDE: path.join(root, ".build/cache/swift") },
  });
  if (result.status !== 0) throw new Error("Could not build the Calendar extension's native helper");
  const bundle = path.join(destination, "helpers/CalendarAdapter.app");
  const contents = path.join(bundle, "Contents");
  await mkdir(path.join(contents, "MacOS"), { recursive: true });
  const binary = path.join(contents, "MacOS/CalendarAdapter");
  await copyFile(path.join(root, ".build/debug/CalendarAdapter"), binary);
  await chmod(binary, 0o755);
  await writeFile(path.join(contents, "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.notchnotch.calendar.adapter</string>
<key>CFBundleName</key><string>NotchNotch Calendar</string>
<key>CFBundleExecutable</key><string>CalendarAdapter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Read your selected calendars to show the next event and its countdown in the notch. This extension does not change your events.</string>
<key>NSCalendarsUsageDescription</key><string>Read your selected calendars to show upcoming events in the notch.</string>
</dict></plist>
`);
  const signed = spawnSync("codesign", ["--force", "--sign", "-", bundle], { stdio: "inherit" });
  if (signed.status !== 0) throw new Error("Could not sign the Calendar extension's helper");
}
