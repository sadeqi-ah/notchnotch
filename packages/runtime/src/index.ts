import type { ReactNode } from "react";
import { createRenderer } from "@notchnotch/react-renderer";
import type { MediaUpdate, UserEvent } from "@notchnotch/protocol";

declare global {
  var __notchnotchExtensionID: string;
  var __notchnotchSend: (json: string) => void;
  var __notchnotchDispatch: (json: string) => void;
}

export function start(element: ReactNode) {
  const extensionID = globalThis.__notchnotchExtensionID;
  const renderer = createRenderer(extensionID,
    (snapshot) => globalThis.__notchnotchSend(JSON.stringify(snapshot)),
    (error) => globalThis.__notchnotchSend(JSON.stringify({
      protocolVersion: 1, type: "error", extensionID,
      message: error instanceof Error ? error.message : String(error),
    })),
  );
  globalThis.__notchnotchDispatch = (json) => {
    const message: UserEvent | MediaUpdate = JSON.parse(json);
    if (message.protocolVersion === 1 && message.type === "media") {
      globalThis.__notchnotchMediaDispatch?.(message);
      return;
    }
    const event = message as UserEvent;
    if (event.protocolVersion !== 1 || event.type !== "event" || typeof event.action !== "string") return;
    renderer.dispatch(event);
  };
  renderer.render(element);
}
