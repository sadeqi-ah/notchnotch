import { build, context } from "esbuild";
import { mkdir, readFile, readdir, copyFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export async function buildExtensions({ watch = false } = {}) {
  const contexts = [];
  for (const name of (await readdir(path.join(root, "extensions"))).sort()) {
    const source = path.join(root, "extensions", name);
    const manifest = JSON.parse(await readFile(path.join(source, "notchnotch.json"), "utf8"));
    if (!/^[a-z][a-z0-9.-]{2,79}$/.test(manifest.id) || manifest.apiVersion !== 1 || manifest.entry !== "bundle.js" || (!Array.isArray(manifest.permissions) || manifest.permissions.some((permission) => permission !== "media"))) {
      throw new Error(`Unsupported manifest: ${name}`);
    }
    const destination = path.join(root, "dist", "extensions", name);
    await mkdir(destination, { recursive: true });
    await copyFile(path.join(source, "notchnotch.json"), path.join(destination, "notchnotch.json"));
    const options = {
      absWorkingDir: root,
      entryPoints: [path.join(source, "src/index.tsx")],
      outfile: path.join(destination, "bundle.js"),
      bundle: true, format: "iife", platform: "neutral", target: "es2022",
      mainFields: ["module", "main"], conditions: ["default"], jsx: "automatic",
      define: { "process.env.NODE_ENV": '"production"' },
      sourcemap: "linked", logLevel: "info",
    };
    if (watch) {
      const instance = await context(options);
      await instance.watch();
      contexts.push(instance);
    } else await build(options);
  }
  return contexts;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) await buildExtensions();
