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
  settings?: UINode;
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

export type MediaCommand = "playPause" | "previous" | "next" | "seek" | "volume" | "shuffle" | "repeat" | "openPlayer";
export interface NowPlayingState {
  id: string;
  eventID: string;
  player: string;
  playerName?: string;
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
export interface MediaRequest { command: MediaCommand; value?: number }

export type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };
export interface ConnectionHTTPRequest {
  path: string;
  method: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD" | "OPTIONS";
  headers?: Record<string, string>;
  body?: string;
  timeoutMs?: number;
}
export interface ConnectionCommand {
  protocolVersion: 1;
  type: "connectionCommand";
  extensionID: string;
  requestID: string;
  connectionID: string;
  operation: "request" | "open" | "send" | "close";
  sessionID?: string;
  request?: ConnectionHTTPRequest;
  message?: JSONValue;
}
export interface ConnectionResponse {
  protocolVersion: 1;
  type: "connectionResponse";
  requestID: string;
  result?: JSONValue;
  error?: string;
}
export interface ConnectionEvent {
  protocolVersion: 1;
  type: "connectionEvent";
  connectionID: string;
  sessionID: string;
  event: "message" | "closed";
  message?: JSONValue;
  error?: string;
}
