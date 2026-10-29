import { useEffect, useMemo, useRef, useState } from "react";
import {
  Activity, Artwork, Button, ConnectionStream, JSONRPCClient, MusicPlayer,
  Row, Settings, Symbol, Text, Waveform,
} from "@notchnotch/sdk";
import type { JSONValue, MediaRequest, NowPlayingState } from "@notchnotch/protocol";
import { start } from "@notchnotch/runtime";

interface MusicStatus {
  state?: NowPlayingState | null;
  authorized: string[];
  errors: Record<string, string>;
  commandError?: string;
}
const players = [
  { id: "com.spotify.client", name: "Spotify" },
  { id: "com.apple.Music", name: "Apple Music" },
];

function Music() {
  const rpc = useMemo(() => new JSONRPCClient(new ConnectionStream("player")), []);
  const [status, setStatus] = useState<MusicStatus | null>(null);
  const [connected, setConnected] = useState(false);
  const active = useRef(false);
  const connecting = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [playbackError, setPlaybackError] = useState("");

  useEffect(() => {
    const stopNotifications = rpc.onNotification(({ method, params }) => {
      if (method === "music/state" && params && typeof params === "object" && !Array.isArray(params)) {
        setStatus(params as unknown as MusicStatus);
      }
    });
    const stopStream = rpc.stream.subscribe((event) => {
      if (event.event === "closed") {
        active.current = false;
        setConnected(false);
        setStatus(null);
        setError(event.error ?? "Music disconnected. Connect again to resume.");
      }
    });
    return () => { stopNotifications(); stopStream(); void rpc.dispose().catch(() => {}); };
  }, [rpc]);

  async function connect(player?: string) {
    if (connecting.current) return;
    connecting.current = true;
    setBusy(true);
    setError("");
    try {
      const snapshot = await rpc.request<MusicStatus>("music/getState");
      active.current = true;
      setConnected(true);
      setStatus(snapshot);
      if (player) setStatus(await rpc.request<MusicStatus>("music/connect", { player }, 120_000));
    } catch (failure) {
      setError(String(failure));
      // A failed handshake must not leave a nonresponsive helper cached for
      // every subsequent Connect attempt.
      if (!active.current) await rpc.disconnect().catch(() => {});
    } finally { connecting.current = false; setBusy(false); }
  }

  function command(request: MediaRequest) {
    if (!active.current) return;
    setPlaybackError("");
    void rpc.request("music/command", request as unknown as JSONValue).catch((failure: unknown) => setPlaybackError(String(failure)));
  }

  const state = connected ? status?.state : null;
  const problem = (error || status?.commandError || Object.values(status?.errors ?? {})[0] || "").slice(0, 1024);
  return <>
    <Settings>
      <Text tone="secondary">Connect a player to show its playback and controls in the notch.</Text>
      <Row>{players.map((player, index) => <Button key={player.id}
        title={`${status?.authorized.includes(player.id) ? "Reconnect" : "Connect"} ${player.name}`}
        tone={index === 0 ? "accent" : "secondary"} disabled={busy}
        onPress={() => { void connect(player.id); }} />)}</Row>
      {busy ? <Text tone="secondary">Waiting for player access…</Text> : null}
      {players.filter((player) => status?.authorized.includes(player.id)).map((player) =>
        <Text key={player.id} tone="secondary">{`${player.name} access granted`}</Text>)}
      {connected && !state ? <Text tone="secondary">Play a track in a connected player to see it in the notch.</Text> : null}
      {problem ? <Text tone="warning">{problem}</Text> : null}
    </Settings>
    {state ? <Activity idlePreview id="now-playing" title={state.title.slice(0, 128)}
      phase={state.isPlaying ? "active" : "paused"}>
      <Activity.Compact leading={<Artwork source={state.artwork} />}
        trailing={state.isPlaying ? <Waveform playing source={state.artwork} /> : <Symbol name="pause.fill" tone="secondary" />} />
      <Activity.Peek id={state.eventID}
        text={(state.artist ? `${state.artist} • ${state.title}` : state.title).slice(0, 256)} />
      <Activity.Expanded>
        <MusicPlayer state={state} onCommand={command} />
        {playbackError || status?.commandError ? <Text tone="warning">{(playbackError || status?.commandError || "").slice(0, 1024)}</Text> : null}
      </Activity.Expanded>
    </Activity> : null}
  </>;
}
start(<Music />);
