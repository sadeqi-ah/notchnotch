import { useState } from "react";
import {
  Activity,
  Button,
  Prompt,
  Row,
  Symbol,
  Text,
  TextField,
} from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

function PromptDemo() {
  const [asking, setAsking] = useState(false);
  const [answer, setAnswer] = useState("");
  const [name, setName] = useState("");
  return (
    <>
      <Activity id="questions" title="Quick question" phase="paused">
        <Activity.Compact
          leading={<Symbol name="bubble.left.and.bubble.right.fill" />}
          trailing={<Text size="caption">Ask</Text>}
        />
        <Activity.Expanded>
          <Row>
            <Symbol name="bubble.left.and.bubble.right.fill" />
            <Text size="caption" tone="secondary">
              A KNOCK, NOT AN INTERRUPTION
            </Text>
          </Row>
          <Text size="title">A small question.</Text>
          <Text tone="secondary">
            Apps can ask for a decision, right here. Your timer keeps going.
          </Text>
          {answer ? <Text tone="success">{answer}</Text> : null}
          <Button
            title={asking ? "Waiting for your answer…" : "Try a prompt"}
            disabled={asking}
            tone="accent"
            onPress={() => {
              setName("");
              setAsking(true);
            }}
          />
        </Activity.Expanded>
      </Activity>
      {asking ? (
        <Prompt
          id="name-session"
          title="Name your session"
          initialView="expanded"
        >
          <Prompt.Expanded>
            <Row>
              <Symbol name="hand.wave.fill" />
              <Text size="caption" tone="secondary">
                QUICK QUESTION
              </Text>
            </Row>
            <Text size="title">What are you working on?</Text>
            <Text tone="secondary">
              Give this focus session a name. You can also come back to this
              later.
            </Text>
            <TextField
              value={name}
              onChange={setName}
              placeholder="e.g. A new beginning"
            />
            <Row>
              <Button
                title="Save name"
                tone="accent"
                disabled={!name.trim()}
                onPress={() => {
                  setAnswer(`Session named “${name.trim()}”.`);
                  setAsking(false);
                }}
              />
              <Button
                title="Skip"
                onPress={() => {
                  setAnswer("Skipped. Your focus is still yours.");
                  setAsking(false);
                }}
              />
            </Row>
          </Prompt.Expanded>
        </Prompt>
      ) : null}
    </>
  );
}
start(<PromptDemo />);
