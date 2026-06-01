"use client";

import { useEffect } from "react";

/** Keys + appliance for user display preferences (persisted across sessions). */
export const PREFS = {
  uiScale: "tvking:uiScale",
  safeScale: "tvking:safeScale",
} as const;

export function applyPrefs() {
  if (typeof window === "undefined") return;
  const root = document.documentElement;
  const ui = window.localStorage.getItem(PREFS.uiScale);
  const safe = window.localStorage.getItem(PREFS.safeScale);
  if (ui) root.style.setProperty("--ui-scale", ui);
  if (safe) root.style.setProperty("--safe-scale", safe);
}

/** Mounted once in the layout so saved preferences apply on every page. */
export default function Preferences() {
  useEffect(() => {
    applyPrefs();
  }, []);
  return null;
}
