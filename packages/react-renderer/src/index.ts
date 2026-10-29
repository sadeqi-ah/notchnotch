import Reconciler from "react-reconciler";
import { DefaultEventPriority, DiscreteEventPriority } from "react-reconciler/constants";
import { createContext, type ReactNode } from "react";
import type { Snapshot, Surface, UINode, UserEvent } from "@notchnotch/protocol";

type Props = Record<string, unknown>;
interface Instance { id: string; type: string; props: Props; children: Instance[]; text?: string }
interface Container { children: Instance[]; commit: () => void }
let nextID = 0;
let eventPriority = DefaultEventPriority;
const hostContext = {};
function append(parent: Instance | Container, child: Instance) {
  parent.children = parent.children.filter((item) => item !== child);
  parent.children.push(child);
}
function remove(parent: Instance | Container, child: Instance) {
  parent.children = parent.children.filter((item) => item !== child);
}
function insert(parent: Instance | Container, child: Instance, before: Instance) {
  remove(parent, child);
  const index = parent.children.indexOf(before);
  parent.children.splice(index < 0 ? parent.children.length : index, 0, child);
}

// Keep this adapter internal: React and react-reconciler are pinned as a pair.
const reconciler = Reconciler({
  rendererVersion: "0.1.0",
  rendererPackageName: "@notchnotch/react-renderer",
  extraDevToolsConfig: null,
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  isPrimaryRenderer: true,
  getRootHostContext: () => hostContext,
  getChildHostContext: () => hostContext,
  getPublicInstance: (instance: Instance) => instance,
  prepareForCommit: () => null,
  resetAfterCommit: (container: Container) => container.commit(),
  createInstance: (type: string, props: Props): Instance => ({ id: `n${++nextID}`, type, props, children: [] }),
  createTextInstance: (text: string): Instance => ({ id: `n${++nextID}`, type: "#text", props: {}, children: [], text }),
  appendInitialChild: append,
  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  appendChild: append,
  appendChildToContainer: append,
  removeChild: remove,
  removeChildFromContainer: remove,
  insertBefore: insert,
  insertInContainerBefore: insert,
  commitUpdate: (instance: Instance, _type: string, _old: Props, props: Props) => { instance.props = props; },
  commitTextUpdate: (instance: Instance, _old: string, text: string) => { instance.text = text; },
  resetTextContent: () => {},
  commitMount: () => {},
  clearContainer: (container: Container) => { container.children = []; },
  detachDeletedInstance: () => {},
  preparePortalMount: () => {},
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,
  noTimeout: -1,
  supportsMicrotasks: true,
  scheduleMicrotask: queueMicrotask,
  getInstanceFromNode: () => null,
  beforeActiveInstanceBlur: () => {},
  afterActiveInstanceBlur: () => {},
  prepareScopeUpdate: () => {},
  getInstanceFromScope: () => null,
  setCurrentUpdatePriority: (priority: number) => { eventPriority = priority; },
  getCurrentUpdatePriority: () => eventPriority,
  resolveUpdatePriority: () => eventPriority || DefaultEventPriority,
  trackSchedulerEvent: () => {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  shouldAttemptEagerTransition: () => false,
  requestPostPaintCallback: (callback: (time: number) => void) => setTimeout(() => callback(performance.now()), 0),
  maySuspendCommit: () => false,
  maySuspendCommitOnUpdate: () => false,
  maySuspendCommitInSyncRender: () => false,
  preloadInstance: () => true,
  startSuspendingCommit: () => {},
  suspendInstance: () => {},
  suspendOnActiveViewTransition: () => {},
  getSuspendedCommitReason: () => null,
  waitForCommitToBeReady: () => null,
  NotPendingTransition: null,
  HostTransitionContext: createContext(null) as unknown as Reconciler.ReactContext<null>,
  resetFormInstance: () => {},
  bindToConsole: (_method: string, args: unknown[]) => () => console.log(...args),
});

const nodeTypes = new Set(["column", "row", "text", "symbol", "progress", "button", "textField", "artwork", "waveform", "player"]);
function plainText(node: Instance): string {
  return node.type === "#text" ? node.text ?? "" : node.children.map(plainText).join("");
}

export function createRenderer(extensionID: string, send: (snapshot: Snapshot) => void, reportError: (error: unknown) => void) {
  let revision = 0;
  let actions = new Map<string, (value?: string) => void>();
  function serialize(node: Instance, registry: typeof actions): UINode {
    if (!nodeTypes.has(node.type)) throw new Error(`Unsupported component: ${node.type}`);
    const props: UINode["props"] = {};
    for (const key of ["text", "name", "tone", "size", "value", "placeholder", "disabled", "source", "media"] as const) {
      if (node.props[key] !== undefined) Object.assign(props, { [key]: node.props[key] });
    }
    if (node.type === "text") props.text = plainText(node);
    const callback = node.props.onPress ?? node.props.onChange;
    if (typeof callback === "function") {
      props.action = `${node.id}:action`;
      registry.set(props.action, callback as (value?: string) => void);
    }
    return {
      id: node.id, type: node.type as UINode["type"], props,
      children: node.type === "text" ? [] : node.children.map((child) => serialize(child, registry)),
    };
  }
  function surface(node: Instance, registry: typeof actions): Surface {
    if (node.type !== "activity" && node.type !== "prompt") throw new Error("An extension root must contain Activity, Prompt or Settings components");
    if (typeof node.props.id !== "string" || typeof node.props.title !== "string") throw new Error("A surface requires a string id and title");
    if (node.children.filter((child) => child.type === "expanded").length !== 1 ||
        node.children.filter((child) => child.type === "compact").length > 1 ||
        node.children.filter((child) => child.type === "peek").length > 1 ||
        node.children.some((child) => !["expanded", "compact", "peek"].includes(child.type))) {
      throw new Error("A surface requires exactly one Expanded, at most one Compact, and at most one Peek child");
    }
    const compact = node.children.find((child) => child.type === "compact");
    const expanded = node.children.find((child) => child.type === "expanded");
    const peek = node.children.find((child) => child.type === "peek");
    if (peek && (node.type !== "activity" || !compact ||
        typeof peek.props.id !== "string" || !peek.props.id.length || peek.props.id.length > 128 ||
        typeof peek.props.text !== "string" || !peek.props.text.length || peek.props.text.length > 256 ||
        typeof peek.props.duration !== "number" || !Number.isFinite(peek.props.duration) ||
        peek.props.duration < 1 || peek.props.duration > 10)) {
      throw new Error("Peek requires an Activity with Compact content, an event id, text, and a duration of 1–10 seconds");
    }
    if (!expanded) throw new Error(`${node.props.id}: Expanded is required`);
    if (!compact && node.props.initialView !== "expanded") throw new Error("A compact initial view requires Compact content");
    if (node.props.idlePreview === true && (node.type !== "activity" || !compact)) {
      throw new Error("Idle previews require an Activity with Compact content");
    }
    return {
      ...(node.props.idlePreview === true ? { idlePreview: true } : {}),
      id: String(node.props.id), kind: node.type, title: String(node.props.title),
      initialView: node.props.initialView as Surface["initialView"], phase: node.props.phase as Surface["phase"],
      ...(compact ? { compact: {
        leading: (compact.children.find((child) => child.type === "leading")?.children ?? []).map((child) => serialize(child, registry)),
        trailing: (compact.children.find((child) => child.type === "trailing")?.children ?? []).map((child) => serialize(child, registry)),
      } } : {}),
      ...(peek ? { peek: { id: peek.props.id as string, text: peek.props.text as string, duration: peek.props.duration as number } } : {}),
      expanded: { id: expanded.id, type: "column", props: {}, children: expanded.children.map((child) => serialize(child, registry)) },
    };
  }
  const container: Container = {
    children: [],
    commit() {
      try {
        const registry = new Map<string, (value?: string) => void>();
        const panels = container.children.filter((node) => node.type === "settings");
        if (panels.length > 1) throw new Error("An extension may expose only one Settings panel");
        const panel = panels[0];
        const settings: UINode | undefined = panel ? {
          id: panel.id, type: "column", props: {}, children: panel.children.map((node) => serialize(node, registry)),
        } : undefined;
        const surfaces = container.children.filter((node) => node.type !== "settings").map((node) => surface(node, registry));
        actions = registry;
        send({ protocolVersion: 1, type: "snapshot", extensionID, revision: ++revision, surfaces, ...(settings ? { settings } : {}) });
      } catch (error) { reportError(error); }
    },
  };
  const root = reconciler.createContainer(container, 1, null, false, null, "", reportError, reportError, reportError, () => {}, null);
  return {
    render(element: ReactNode) { reconciler.updateContainerSync(element, root, null, null); reconciler.flushSyncWork(); },
    dispatch(event: UserEvent) {
      const callback = actions.get(event.action);
      if (!callback) return;
      const previous = eventPriority;
      eventPriority = DiscreteEventPriority;
      try {
        reconciler.flushSyncFromReconciler(() => callback(event.value));
      } catch (error) { reportError(error); }
      finally { eventPriority = previous; }
    },
  };
}
