import { useEffect, useState } from "react";
import { Activity, Button, Prompt, Text, TextField } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

// Test-only React state, timer and input callbacks across the runner boundary.
function RuntimeFixture() {
  const [remaining, setRemaining] = useState(5);
  const [running, setRunning] = useState(false);
  const [asking, setAsking] = useState(false);
  const [name, setName] = useState("");
  const [answer, setAnswer] = useState("");
  useEffect(() => {
    if (!running) return;
    const tick = setInterval(() => setRemaining((value) => Math.max(0, value - 1)), 1000);
    return () => clearInterval(tick);
  }, [running]);
  return <>
    <Activity id="runtime" title="Runtime fixture" phase={running ? "active" : "paused"}>
      <Activity.Compact leading={<Text>Test</Text>} trailing={<Text>{remaining}</Text>} />
      <Activity.Peek id="ready" text="Runtime ready" />
      <Activity.Expanded>
        <Text>{answer}</Text>
        <Button title={running ? "Pause" : "Start"} onPress={() => setRunning((value) => !value)} />
        <Button title="Reset" onPress={() => { setRunning(false); setRemaining(5); }} />
        <Button title="Ask" onPress={() => setAsking(true)} />
      </Activity.Expanded>
    </Activity>
    {asking ? <Prompt id="input" title="Runtime input" initialView="expanded">
      <Prompt.Expanded>
        <TextField value={name} onChange={setName} placeholder="Test input" />
        <Button title="Save" onPress={() => { setAnswer(name); setAsking(false); }} />
      </Prompt.Expanded>
    </Prompt> : null}
  </>;
}
start(<RuntimeFixture />);
