// The extension runtime deliberately exposes neither Node nor browser globals.
declare function setTimeout<Args extends unknown[]>(callback: (...args: Args) => void, delay?: number, ...args: Args): number;
declare function setInterval<Args extends unknown[]>(callback: (...args: Args) => void, delay?: number, ...args: Args): number;
declare function clearTimeout(identifier: number | undefined): void;
declare function clearInterval(identifier: number | undefined): void;
declare function queueMicrotask(callback: () => void): void;
declare const performance: { now(): number };
declare const console: {
  log(...args: unknown[]): void;
  info(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
  debug(...args: unknown[]): void;
};
