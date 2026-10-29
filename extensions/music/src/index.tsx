import {
  Activity,
  Artwork,
  MusicPlayer,
  Symbol,
  Waveform,
  controlMedia,
  useNowPlaying,
} from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

function Music() {
  const state = useNowPlaying();
  if (!state) return null;
  return (
    <Activity
      idlePreview
      id="now-playing"
      title={state.title.slice(0, 128)}
      phase={state.isPlaying ? "active" : "paused"}
    >
      <Activity.Compact
        leading={<Artwork source={state.artwork} />}
        trailing={
          state.isPlaying ? (
            <Waveform playing source={state.artwork} />
          ) : (
            <Symbol name="pause.fill" tone="secondary" />
          )
        }
      />
      <Activity.Peek
        id={state.eventID}
        text={(state.artist
          ? `${state.artist} • ${state.title}`
          : state.title
        ).slice(0, 256)}
      />
      <Activity.Expanded>
        <MusicPlayer state={state} onCommand={controlMedia} />
      </Activity.Expanded>
    </Activity>
  );
}
start(<Music />);
