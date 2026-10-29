export const PROTOCOL_VERSION = 1 as const;
export const MAX_MESSAGE_BYTES = 262_144;
export type Tone = "primary" | "secondary" | "accent" | "success" | "warning";
export type TextSize = "caption" | "body" | "title" | "timer";
export type NodeType = "column" | "row" | "text" | "symbol" | "progress" | "button" | "textField" | "artwork" | "waveform" | "player";
export interface UINode {
  id: string;
  type: NodeType;
  props: {
    text?: string;
    name?: string;
    tone?: Tone;
    size?: TextSize;
    value?: number;
    action?: string;
    placeholder?: string;
    disabled?: boolean;
    source?: string;
    media?: NowPlayingState;
  };
  children: UINode[];
}
export interface PeekContent {
  /** Change for each new event; keep stable during routine renders. */
  id: string;
  text: string;
  duration: number;
}
export interface Surface {
  id: string;
  kind: "activity" | "prompt";
  title: string;
  initialView: "compact" | "expanded";
  phase: "active" | "paused" | "completed" | "pending";
  compact?: { leading: UINode[]; trailing: UINode[] };
  expanded: UINode;
  peek?: PeekContent;
  idlePreview?: boolean;
}
export interface Snapshot {
  protocolVersion: 1;
  type: "snapshot";
  extensionID: string;
  revision: number;
  surfaces: Surface[];
}
export interface UserEvent {
  protocolVersion: 1;
  type: "event";
  action: string;
  value?: string;
}
export interface RuntimeNotice {
  protocolVersion: 1;
  type: "error" | "log";
  extensionID: string;
  message: string;
}

export type MediaPlayer = "com.spotify.client" | "com.apple.Music";
export type MediaCommand = "playPause" | "previous" | "next" | "seek" | "volume" | "shuffle" | "repeat" | "openPlayer";
export interface NowPlayingState {
  id: string;
  eventID: string;
  player: MediaPlayer;
  title: string;
  artist: string;
  album: string;
  artwork?: string;
  duration: number;
  position: number;
  isPlaying: boolean;
  volume: number;
  shuffle: boolean;
  repeating: boolean;
  updatedAt: number;
}
export interface MediaUpdate {
  protocolVersion: 1;
  type: "media";
  state?: NowPlayingState | null;
}
export interface MediaRequest { command: MediaCommand; value?: number }
