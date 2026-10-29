const allowedPermissions = new Set(["local-network", "process"]);

export function validateManifest(manifest) {
  const invalid = () => { throw new Error(`Unsupported manifest: ${manifest.id ?? "unknown"}`); };
  if (!/^[a-z][a-z0-9.-]{2,79}$/.test(manifest.id) || typeof manifest.name !== "string" || !manifest.name ||
      manifest.apiVersion !== 1 || manifest.entry !== "bundle.js" || !Array.isArray(manifest.permissions) ||
      new Set(manifest.permissions).size !== manifest.permissions.length ||
      manifest.permissions.some((permission) => !allowedPermissions.has(permission))) invalid();
  const connections = manifest.connections ?? {};
  if (!connections || typeof connections !== "object" || Array.isArray(connections) || Object.keys(connections).length > 8) invalid();
  for (const [id, value] of Object.entries(connections)) {
    if (!/^[a-z][a-z0-9-]{0,63}$/.test(id) || !value || typeof value !== "object") invalid();
    if (["http", "websocket"].includes(value.transport)) {
      let url;
      try { url = new URL(value.endpoint); } catch { invalid(); }
      const schemes = value.transport === "http" ? ["http:", "https:"] : ["ws:", "wss:"];
      if (!manifest.permissions.includes("local-network") || value.executable !== undefined || value.arguments !== undefined ||
          !schemes.includes(url.protocol) || !["127.0.0.1", "[::1]"].includes(url.hostname) ||
          url.username || url.password || url.search || url.hash || (value.transport === "http" && url.pathname !== "/")) invalid();
      // Reject alternate IP encodings that WHATWG URL silently normalizes.
      const pattern = value.transport === "http"
        ? /^https?:\/\/(?:127\.0\.0\.1|\[::1\]):([0-9]+)\/?$/
        : /^wss?:\/\/(?:127\.0\.0\.1|\[::1\]):([0-9]+)(\/[^?#]*)?$/;
      const origin = pattern.exec(value.endpoint);
      if (!origin || Number(origin[1]) < 1 || Number(origin[1]) > 65535) invalid();
    } else if (value.transport === "stdio") {
      const executable = value.executable;
      if (!manifest.permissions.includes("process") || value.endpoint !== undefined ||
          typeof executable !== "string" || !executable || Buffer.byteLength(executable) > 1024 || executable.includes("\0") ||
          !(executable.startsWith("/") || !executable.includes("/") ||
            (executable.startsWith("./") && !executable.split("/").includes(".."))) ||
          (value.arguments !== undefined && (!Array.isArray(value.arguments) || value.arguments.length > 32 ||
            value.arguments.some((argument) => typeof argument !== "string" || argument.includes("\0") || Buffer.byteLength(argument) > 4096)))) invalid();
    } else invalid();
  }
}
