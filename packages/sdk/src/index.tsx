import { createElement, type ReactNode } from "react";
import type { MediaRequest, NowPlayingState, TextSize, Tone } from "@notchnotch/protocol";
export * from "./connections";

type Children = { children?: ReactNode };
type SurfaceProps = Children & {
  id: string;
  title: string;
  initialView?: "compact" | "expanded";
};
function Compact({ leading, trailing }: { leading: ReactNode; trailing: ReactNode }) {
  return createElement("compact", null,
    createElement("leading", null, leading), createElement("trailing", null, trailing));
}
function Expanded({ children }: Children) { return createElement("expanded", null, children); }

/** Show a short announcement, then return to Compact. A new id starts a new event. */
function Peek({ id, text, duration = 4 }: { id: string; text: string; duration?: number }) {
  return createElement("peek", { id, text, duration });
}

/** The entire compact surface is one host-owned click target. */
export const Activity = Object.assign(
  function Activity({ initialView = "compact", phase = "active", ...props }: SurfaceProps & {
    phase?: "active" | "paused" | "completed";
    /** Eligible as a hover fallback even before this activity has been used. */
    idlePreview?: boolean;
  }) { return createElement("activity", { ...props, initialView, phase }); },
  { Compact, Expanded, Peek },
);

/** Unmount a prompt after recording its answer; collapsing it does not answer it. */
export const Prompt = Object.assign(
  function Prompt({ initialView = "expanded", ...props }: SurfaceProps) {
    return createElement("prompt", { ...props, initialView, phase: "pending" });
  },
  { Compact, Expanded },
);
export function Column({ children }: Children) { return createElement("column", null, children); }
export function Row({ children }: Children) { return createElement("row", null, children); }
export function Text({ children, tone = "primary", size = "body" }: Children & { tone?: Tone; size?: TextSize }) {
  return createElement("text", { tone, size }, children);
}
export function Symbol({ name, tone = "accent" }: { name: string; tone?: Tone }) {
  return createElement("symbol", { name, tone });
}
export function Progress({ value, tone = "accent" }: { value: number; tone?: Tone }) {
  return createElement("progress", { value, tone });
}
export function Button({ title, onPress, tone = "secondary", disabled = false }: {
  title: string; onPress: () => void; tone?: Tone; disabled?: boolean;
}) { return createElement("button", { text: title, onPress, tone, disabled }); }
export function TextField({ value, onChange, placeholder }: {
  value: string; onChange: (value: string) => void; placeholder: string;
}) { return createElement("textField", { text: value, onChange, placeholder }); }


export function Artwork({ source }: { source?: string }) { return createElement("artwork", { source }); }
export function Waveform({ playing, source }: { playing: boolean; source?: string }) {
  return createElement("waveform", { value: playing ? 1 : 0, source });
}
export function MusicPlayer({ state, onCommand }: { state: NowPlayingState; onCommand: (request: MediaRequest) => void }) {
  return createElement("player", { media: state, onChange: (json?: string) => {
    if (json) onCommand(JSON.parse(json) as MediaRequest);
  } });
}
