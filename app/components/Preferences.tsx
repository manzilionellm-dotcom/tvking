"use client";

import { useEffect } from "react";

/** Keys + appliance for user display preferences (persisted across sessions). */
export const PREFS = {
  uiScale: "tvking:uiScale",
  safeScale: "tvking:safeScale",
  comfort: "tvking:comfort",
} as const;

/*
 * Eye-comfort levels (research §3): in a dark room a TV should sit around
 * 120-180 nits, and a warmer white point cuts blue light by roughly a fifth.
 * A web app cannot touch the panel backlight, so the same two effects are
 * applied in software — a black veil (perceived luminance) and a warm veil
 * (colour temperature) — both very light, and off by default.
 */
export const COMFORT_LEVELS = {
  off: { dim: "0", warm: "0" },
  doux: { dim: "0.08", warm: "0.05" },
  nuit: { dim: "0.18", warm: "0.12" },
} as const;

export type ComfortLevel = keyof typeof COMFORT_LEVELS;

export function isComfortLevel(v: string | null): v is ComfortLevel {
  return v !== null && Object.prototype.hasOwnProperty.call(COMFORT_LEVELS, v);
}

export function applyComfort(level: string | null) {
  if (typeof document === "undefined") return;
  const { dim, warm } = COMFORT_LEVELS[isComfortLevel(level) ? level : "off"];
  const root = document.documentElement;
  root.style.setProperty("--comfort-dim", dim);
  root.style.setProperty("--comfort-warm", warm);
}

export function applyPrefs() {
  if (typeof window === "undefined") return;
  const root = document.documentElement;
  const ui = window.localStorage.getItem(PREFS.uiScale);
  const safe = window.localStorage.getItem(PREFS.safeScale);
  if (ui) root.style.setProperty("--ui-scale", ui);
  if (safe) root.style.setProperty("--safe-scale", safe);
  applyComfort(window.localStorage.getItem(PREFS.comfort));
}

/** Mounted once in the layout so saved preferences apply on every page. */
export default function Preferences() {
  useEffect(() => {
    applyPrefs();
  }, []);
  return null;
}
