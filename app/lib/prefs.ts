"use client";

/*
 * Display preferences (text size + overscan), read via useSyncExternalStore so
 * components stay pure (no setState-in-effect to hydrate from localStorage) and
 * every reader updates when the value changes. Applied live as CSS variables.
 */

import { useSyncExternalStore } from "react";

export const PREF_KEYS = {
  uiScale: "tvking:uiScale",
  safeScale: "tvking:safeScale",
} as const;

type PrefName = "uiScale" | "safeScale";
const CSS_VAR: Record<PrefName, string> = {
  uiScale: "--ui-scale",
  safeScale: "--safe-scale",
};

const listeners = new Set<() => void>();

function readRaw(name: PrefName): number {
  if (typeof window === "undefined") return 1;
  const v = parseFloat(window.localStorage.getItem(PREF_KEYS[name]) || "1");
  return Number.isNaN(v) ? 1 : v;
}

export function getPref(name: PrefName): number {
  return readRaw(name);
}

export function setPref(name: PrefName, value: number): void {
  window.localStorage.setItem(PREF_KEYS[name], String(value));
  document.documentElement.style.setProperty(CSS_VAR[name], String(value));
  for (const l of listeners) l();
}

/** Apply persisted prefs to the document (call once on mount). */
export function applyPrefs(): void {
  if (typeof window === "undefined") return;
  document.documentElement.style.setProperty(CSS_VAR.uiScale, String(readRaw("uiScale")));
  document.documentElement.style.setProperty(CSS_VAR.safeScale, String(readRaw("safeScale")));
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  window.addEventListener("storage", cb);
  return () => {
    listeners.delete(cb);
    window.removeEventListener("storage", cb);
  };
}

/** Reactively read a preference (server snapshot is the neutral 1). */
export function usePref(name: PrefName): number {
  return useSyncExternalStore(
    subscribe,
    () => readRaw(name),
    () => 1
  );
}
