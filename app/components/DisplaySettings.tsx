"use client";

import { setPref, usePref } from "../lib/prefs";

/*
 * Viewer-tunable display: text size + overscan compensation, persisted and
 * applied live via CSS variables (--ui-scale / --safe-scale). Mirrors the
 * "Appearance" controls reference TV apps expose so users can fit any panel.
 */
const STEPS = [0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.2];

function nearestStep(v: number): number {
  const i = STEPS.indexOf(v);
  if (i !== -1) return i;
  // snap to closest step for arbitrary stored values
  let best = 3;
  let bestD = Infinity;
  STEPS.forEach((s, idx) => {
    const d = Math.abs(s - v);
    if (d < bestD) {
      bestD = d;
      best = idx;
    }
  });
  return best;
}

function Stepper({
  label,
  name,
}: {
  label: string;
  name: "uiScale" | "safeScale";
}) {
  const value = usePref(name);
  const i = nearestStep(value);
  return (
    <div className="flex items-center justify-between gap-[1rem] rounded-[var(--radius)] bg-[var(--surface-1)] px-[1.1rem] py-[0.9rem]">
      <span className="text-[1.1rem] font-semibold text-[var(--text-high)]">{label}</span>
      <div className="flex items-center gap-[0.8rem]">
        <button
          data-focusable
          onClick={() => setPref(name, STEPS[Math.max(0, i - 1)])}
          className="focusable h-[2.6rem] w-[2.6rem] rounded-full bg-[var(--surface-3)] text-[1.3rem] font-bold text-[var(--text-high)]"
          aria-label={`Diminuer ${label}`}
        >
          −
        </button>
        <span className="w-[4rem] text-center text-[1.1rem] tabular-nums text-[var(--text-high)]">
          {Math.round(value * 100)} %
        </span>
        <button
          data-focusable
          onClick={() => setPref(name, STEPS[Math.min(STEPS.length - 1, i + 1)])}
          className="focusable h-[2.6rem] w-[2.6rem] rounded-full bg-[var(--surface-3)] text-[1.3rem] font-bold text-[var(--text-high)]"
          aria-label={`Augmenter ${label}`}
        >
          +
        </button>
      </div>
    </div>
  );
}

export default function DisplaySettings() {
  return (
    <div className="flex max-w-[44rem] flex-col gap-[0.7rem]">
      <Stepper label="Taille du texte" name="uiScale" />
      <Stepper label="Marge (overscan)" name="safeScale" />
    </div>
  );
}
