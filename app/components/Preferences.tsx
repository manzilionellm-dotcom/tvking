"use client";

import { useEffect } from "react";
import { applyPrefs } from "../lib/prefs";

export { PREF_KEYS as PREFS } from "../lib/prefs";

/** Mounted once in the layout so saved display preferences apply on every page. */
export default function Preferences() {
  useEffect(() => {
    applyPrefs();
  }, []);
  return null;
}
