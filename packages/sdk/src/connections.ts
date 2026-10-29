import type { ConnectionCommand, ConnectionEvent, ConnectionHTTPRequest, ConnectionResponse, JSONValue } from "@notchnotch/protocol";
export type { JSONValue } from "@notchnotch/protocol";

declare global {
  var __notchnotchSend: (json: string) => void;
  var __notchnotchExtensionID: string;
  var __notchnotchConnectionDispatch: ((message: ConnectionResponse | ConnectionEvent) => void) | undefined;
}

let serial = 0;
const pending = new Map<string, { resolve: (value: JSONValue) => void; reject: (error: Error) => void; timer: number }>();
const listeners = new Set<(event: ConnectionEvent) => void>();

globalThis.__notchnotchConnectionDispatch = (message) => {
  if (message.type === "connectionEvent") {
    for (const listener of listeners) listener(message);
    return;
  }
  const request = pending.get(message.requestID);
  if (!request) return;
  clearTimeout(request.timer);
  pending.delete(message.requestID);
  if (message.error) request.reject(new Error(message.error));
  else request.resolve(message.result ?? null);
};

function command(connectionID: string, operation: ConnectionCommand["operation"],
                 fields: Pick<ConnectionCommand, "request" | "message" | "sessionID"> = {}, timeoutMs = 35_000): Promise<JSONValue> {
  if (pending.size >= 32) return Promise.reject(new Error("Too many pending connection operations"));
  const requestID = `connection-${++serial}`;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(requestID);
      reject(new Error(`Connection operation timed out: ${connectionID}`));
    }, timeoutMs);
    pending.set(requestID, { resolve, reject, timer });
    try {
      globalThis.__notchnotchSend(JSON.stringify({ protocolVersion: 1, type: "connectionCommand",
        extensionID: globalThis.__notchnotchExtensionID, requestID, connectionID, operation, ...fields } satisfies ConnectionCommand));
    } catch (error) {
      clearTimeout(timer); pending.delete(requestID);
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

export interface LocalHTTPResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export function localHTTP(connectionID: string) {
  return {
    async request(path: string, options: Omit<Partial<ConnectionHTTPRequest>, "path"> = {}): Promise<LocalHTTPResponse> {
      return await command(connectionID, "request", { request: { path, method: "GET", ...options } }) as unknown as LocalHTTPResponse;
    },
  };
}

/** One manifest-declared WebSocket or JSONL subprocess. Subscribe before opening. */
export class ConnectionStream {
  private sessionID: string | undefined;
  private opening: Promise<void> | undefined;
  private generation = 0;
  private subscribers = new Set<(event: ConnectionEvent) => void>();
  private readonly dispatch = (event: ConnectionEvent) => {
    if (event.connectionID !== this.connectionID || event.sessionID !== this.sessionID) return;
    if (event.event === "closed") { this.sessionID = undefined; this.opening = undefined; }
    for (const listener of this.subscribers) listener(event);
  };

  constructor(readonly connectionID: string) { listeners.add(this.dispatch); }

  open(): Promise<void> {
    if (this.opening) return this.opening;
    if (this.sessionID) return Promise.resolve();
    const sessionID = `stream-${++serial}`;
    const generation = ++this.generation;
    this.sessionID = sessionID;
    this.opening = command(this.connectionID, "open", { sessionID }, 120_000).then(() => {
      if (generation !== this.generation || this.sessionID !== sessionID) throw new Error("Connection closed while opening");
      this.opening = undefined;
    }).catch((error: unknown) => {
      if (generation === this.generation) { this.sessionID = undefined; this.opening = undefined; }
      void command(this.connectionID, "close", { sessionID }).catch(() => {});
      throw error;
    });
    return this.opening;
  }

  async send(message: JSONValue): Promise<void> {
    await this.open();
    await command(this.connectionID, "send", { sessionID: this.sessionID, message });
  }

  subscribe(listener: (event: ConnectionEvent) => void): () => void {
    this.subscribers.add(listener);
    return () => { this.subscribers.delete(listener); };
  }

  async close(): Promise<void> {
    const sessionID = this.sessionID;
    this.sessionID = undefined; this.opening = undefined; this.generation++;
    if (sessionID) await command(this.connectionID, "close", { sessionID });
  }

  async dispose(): Promise<void> {
    try { await this.close(); }
    finally { listeners.delete(this.dispatch); this.subscribers.clear(); }
  }
}

export type RPCID = string | number;
export interface RPCRequest { id: RPCID; method: string; params?: JSONValue }
export interface RPCNotification { method: string; params?: JSONValue }

/** Bidirectional JSON-RPC. Server requests stay pending until respond/reject is called. */
export class JSONRPCClient {
  private serial = 0;
  private generation = 0;
  private requests = new Map<string, { resolve: (result: JSONValue) => void; reject: (error: Error) => void; timer: number }>();
  private notifications = new Set<(message: RPCNotification) => void>();
  private serverRequests = new Set<(message: RPCRequest) => void>();
  private readonly unsubscribe: () => void;

  constructor(readonly stream: ConnectionStream, private readonly options: { includeVersion?: boolean } = {}) {
    this.unsubscribe = stream.subscribe((event) => {
      if (event.event === "closed") { this.generation++; this.cancelPending(new Error(event.error ?? "Connection closed")); return; }
      const value = event.message;
      if (!value || typeof value !== "object" || Array.isArray(value)) return;
      const id = value.id;
      if (typeof value.method === "string") {
        if (typeof id === "number" || typeof id === "string") {
          const request: RPCRequest = { id, method: value.method, params: value.params };
          if (this.serverRequests.size) for (const listener of this.serverRequests) listener(request);
          else void this.reject(id, -32601, "Client does not handle this request").catch(() => {});
        } else {
          for (const listener of this.notifications) listener({ method: value.method, params: value.params });
        }
      } else if (typeof id === "string") {
        const request = this.requests.get(id);
        if (!request) return;
        this.requests.delete(id); clearTimeout(request.timer);
        if (value.error) request.reject(new Error(JSON.stringify(value.error)));
        else request.resolve(value.result ?? null);
      }
    });
  }

  connect(): Promise<void> { return this.stream.open(); }

  async request<T = JSONValue>(method: string, params?: JSONValue, timeoutMs = 30_000): Promise<T> {
    const generation = this.generation;
    await this.connect();
    if (generation !== this.generation) throw new Error("Disconnected while preparing RPC request");
    if (this.requests.size >= 32) return Promise.reject(new Error("Too many pending RPC requests"));
    const id = `rpc-${++this.serial}`;
    return new Promise<JSONValue>((resolve, reject) => {
      const timer = setTimeout(() => { this.requests.delete(id); reject(new Error(`RPC timed out: ${method}`)); }, timeoutMs);
      this.requests.set(id, { resolve, reject, timer });
      void this.stream.send(this.envelope({ id, method, ...(params === undefined ? {} : { params }) })).catch((error: unknown) => {
        if (!this.requests.delete(id)) return;
        clearTimeout(timer); reject(error instanceof Error ? error : new Error(String(error)));
      });
    }) as Promise<T>;
  }

  notify(method: string, params?: JSONValue): Promise<void> {
    return this.stream.send(this.envelope({ method, ...(params === undefined ? {} : { params }) }));
  }
  respond(id: RPCID, result: JSONValue): Promise<void> { return this.stream.send(this.envelope({ id, result })); }
  reject(id: RPCID, code: number, message: string): Promise<void> {
    return this.stream.send(this.envelope({ id, error: { code, message } }));
  }
  onNotification(listener: (message: RPCNotification) => void): () => void {
    this.notifications.add(listener); return () => { this.notifications.delete(listener); };
  }
  onRequest(listener: (message: RPCRequest) => void): () => void {
    this.serverRequests.add(listener); return () => { this.serverRequests.delete(listener); };
  }
  async disconnect(): Promise<void> {
    this.generation++;
    this.cancelPending(new Error("Disconnected"));
    await this.stream.close();
  }
  async dispose(): Promise<void> {
    this.generation++;
    this.unsubscribe(); this.notifications.clear(); this.serverRequests.clear();
    this.cancelPending(new Error("Disposed")); await this.stream.dispose();
  }
  private envelope(fields: { [key: string]: JSONValue }): JSONValue {
    return this.options.includeVersion === false ? fields : { jsonrpc: "2.0", ...fields };
  }
  private cancelPending(error: Error) {
    for (const request of this.requests.values()) { clearTimeout(request.timer); request.reject(error); }
    this.requests.clear();
  }
}
