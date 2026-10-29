import { build, context } from "esbuild";
import { mkdir, readFile, readdir, copyFile, cp, stat, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { validateManifest } from "./manifest.mjs";

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export async function buildExtensions({ watch = false } = {}) {
  const contexts = [];
  const names = (await readdir(path.join(root, "extensions"))).sort();
  const output = path.join(root, "dist/extensions");
  await mkdir(output, { recursive: true });
  for (const name of await readdir(output)) {
    if (!names.includes(name)) await rm(path.join(output, name), { recursive: true, force: true });
  }
  for (const name of names) {
    const source = path.join(root, "extensions", name);
    const manifest = JSON.parse(await readFile(path.join(source, "notchnotch.json"), "utf8"));
    validateManifest(manifest);
    const destination = path.join(root, "dist", "extensions", name);
    await mkdir(destination, { recursive: true });
    // Build-time code belongs to the extension. Packaged extensions contain only
    // its output; the host never imports or executes this module at runtime.
    const builder = path.join(source, "build.mjs");
    if (await stat(builder).then((value) => value.isFile(), () => false)) {
      await (await import(pathToFileURL(builder).href)).build({ root, source, destination });
    }
    await copyFile(path.join(source, "notchnotch.json"), path.join(destination, "notchnotch.json"));
    const helpers = path.join(source, "helpers");
    if (await stat(helpers).then((value) => value.isDirectory(), () => false)) {
      await cp(helpers, path.join(destination, "helpers"), { recursive: true });
    }
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
