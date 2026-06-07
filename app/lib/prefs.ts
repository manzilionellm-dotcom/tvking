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

/* ----------------------------- boolean prefs ------------------------------ *
 * Réglages on/off (ex. « reprendre la dernière chaîne au démarrage »).
 * Stockés "1"/"0" ; toute valeur absente retombe sur la valeur par défaut.
 * Même bus de listeners que les prefs numériques (re-render synchronisé).
 * -------------------------------------------------------------------------- */
export const BOOL_PREF_KEYS = {
  resumeLast: "tvking:resumeLast",
} as const;

export type BoolPrefName = keyof typeof BOOL_PREF_KEYS;

function readBool(name: BoolPrefName, fallback: boolean): boolean {
  if (typeof window === "undefined") return fallback;
  const v = window.localStorage.getItem(BOOL_PREF_KEYS[name]);
  if (v === "1") return true;
  if (v === "0") return false;
  return fallback;
}

export function getBoolPref(name: BoolPrefName, fallback = true): boolean {
  return readBool(name, fallback);
}

export function setBoolPref(name: BoolPrefName, value: boolean): void {
  window.localStorage.setItem(BOOL_PREF_KEYS[name], value ? "1" : "0");
  for (const l of listeners) l();
}

/** Reactively read a boolean preference (server snapshot = fallback). */
export function useBoolPref(name: BoolPrefName, fallback = true): boolean {
  return useSyncExternalStore(
    subscribe,
    () => readBool(name, fallback),
    () => fallback,
  );
}
