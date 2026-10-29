import { useEffect, useState } from "react";
import { Activity, Button, Progress, Row, Symbol, Text } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

const DURATION = 5 * 60;
function TimerActivity() {
  const [remaining, setRemaining] = useState(DURATION);
  const [running, setRunning] = useState(false);
  useEffect(() => {
    if (!running) return;
    // Derive time from a deadline so a busy event loop never stretches the timer.
    const deadline = Date.now() + remaining * 1000;
    const tick = setInterval(() => {
      const next = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      setRemaining(next);
      if (next === 0) setRunning(false);
    }, 200);
    return () => clearInterval(tick);
  }, [running]);
  const time = `${Math.floor(remaining / 60).toString().padStart(2, "0")}:${(remaining % 60).toString().padStart(2, "0")}`;
  const finished = remaining === 0;
  return (
    <Activity id="focus" title="Focus timer" phase={finished ? "completed" : running ? "active" : "paused"}>
      <Activity.Compact
        leading={<Symbol name={finished ? "checkmark.circle.fill" : "timer"} tone={finished ? "success" : "accent"} />}
        trailing={<Text size="caption" tone={running ? "accent" : "secondary"}>{time}</Text>}
      />
      <Activity.Peek id={finished ? "finished" : "ready"} text={finished ? "Focus complete • Time for a break" : "Focus timer • Ready when you are"} />
      <Activity.Expanded>
        <Row><Symbol name="scope" /><Text size="caption" tone="secondary">A LITTLE SPACE TO FOCUS</Text></Row>
        <Text size="timer">{time}</Text>
        <Text tone="secondary">{finished ? "A little progress. A well-earned pause." : running ? "One thing at a time. You’ve got this." : "Five minutes. One clear intention."}</Text>
        <Progress value={(DURATION - remaining) / DURATION} />
        <Row>
          <Button title={finished ? "Start again" : running ? "Pause" : "Start focus"} tone="accent" onPress={() => {
            if (finished) setRemaining(DURATION);
            setRunning((value) => !value);
          }} />
          <Button title="Reset" onPress={() => { setRunning(false); setRemaining(DURATION); }} />
        </Row>
      </Activity.Expanded>
    </Activity>
  );
}
start(<TimerActivity />);
