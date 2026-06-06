"use client";

/*
 * A pure "current time" hook. Reading Date.now() during render is impure, so we
 * keep a single ticking value in a module store and expose it via
 * useSyncExternalStore — components read a stable snapshot that updates on a
 * timer (used by the guide's live highlight and progress bars).
 */

import { useSyncExternalStore } from "react";

let now = Date.now();
const listeners = new Set<() => void>();
let timer: ReturnType<typeof setInterval> | null = null;

function start() {
  if (timer) return;
  timer = setInterval(() => {
    now = Date.now();
    for (const l of listeners) l();
  }, 30_000);
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  start();
  return () => {
    listeners.delete(cb);
    if (listeners.size === 0 && timer) {
      clearInterval(timer);
      timer = null;
    }
  };
}

export function useNow(): number {
  return useSyncExternalStore(
    subscribe,
    () => now,
    () => now
  );
}
