"use client";

import { useSyncExternalStore } from "react";
import { PREFS } from "../../components/Preferences";
import { useI18n } from "../../i18n/provider";

/*
 * Tiny external store over localStorage so the controls read/write persisted
 * prefs without setState-in-effect, and stay hydration-safe (server snapshot
 * returns the default, client reconciles after mount).
 */
const listeners = new Set<() => void>();
function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}
function readPref(key: string) {
  return typeof window === "undefined" ? "1" : localStorage.getItem(key) ?? "1";
}
function writePref(key: string, cssVar: string, value: string) {
  localStorage.setItem(key, value);
  document.documentElement.style.setProperty(cssVar, value);
  listeners.forEach((l) => l());
}
function usePref(key: string) {
  return useSyncExternalStore(subscribe, () => readPref(key), () => "1");
}

/*
 * Réglages — lets the viewer adapt the UI to their own television and seating:
 * - Taille du texte: scales the rem base (legibility at distance).
 * - Marge de sécurité: compensates for TV overscan that crops screen edges
 *   (the tvOS overscanCompensationInsets / Android overscan problem).
 * Both persist to localStorage and apply live via CSS variables.
 */

type Opt = { label: string; value: string; hint: string };

const TEXT_VALUES = { compact: "0.9", standard: "1", large: "1.15", xlarge: "1.3" } as const;
const SAFE_VALUES = { low: "0.6", standard: "1", high: "1.4" } as const;

function Group({
  title,
  desc,
  opts,
  current,
  onPick,
}: {
  title: string;
  desc: string;
  opts: Opt[];
  current: string;
  onPick: (v: string) => void;
}) {
  return (
    <section className="mb-[2.4rem]">
      <h2 className="text-[1.6rem] font-bold text-[var(--text-high)]">{title}</h2>
      <p className="mb-[1rem] text-[1.2rem] text-[var(--text-medium)]">{desc}</p>
      <div className="flex flex-wrap gap-[0.9rem]">
        {opts.map((o) => {
          const active = current === o.value;
          return (
            <button
              key={o.value}
              data-focusable
              onClick={() => onPick(o.value)}
              className="focusable flex min-w-[11rem] flex-col items-start rounded-[var(--radius)] px-[1.3rem] py-[0.9rem] text-left"
              style={{
                background: active ? "var(--gold-grad)" : "var(--surface-2)",
                color: active ? "#000" : "var(--text-high)",
              }}
            >
              <span className="text-[1.25rem] font-bold">{o.label}</span>
              <span
                className="text-[1rem]"
                style={{ color: active ? "rgba(0,0,0,0.7)" : "var(--text-medium)" }}
              >
                {o.hint}
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

export default function ReglagesPage() {
  const { m } = useI18n();
  const opts = (values: Record<string, string>, labels: Record<string, string[]>): Opt[] =>
    Object.entries(values).map(([k, value]) => ({ value, label: labels[k][0], hint: labels[k][1] }));
  const TEXT_OPTS = opts(TEXT_VALUES, m.settings.text);
  const SAFE_OPTS = opts(SAFE_VALUES, m.settings.safe);
  const ui = usePref(PREFS.uiScale);
  const safe = usePref(PREFS.safeScale);

  const pickUi = (v: string) => writePref(PREFS.uiScale, "--ui-scale", v);
  const pickSafe = (v: string) => writePref(PREFS.safeScale, "--safe-scale", v);

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {m.settings.title}
      </h1>
      <p className="mb-[2.2rem] text-[1.3rem] text-[var(--text-medium)]">
        {m.settings.intro}
      </p>

      <Group
        title={m.settings.textTitle}
        desc={m.settings.textDesc}
        opts={TEXT_OPTS}
        current={ui}
        onPick={pickUi}
      />
      <Group
        title={m.settings.safeTitle}
        desc={m.settings.safeDesc}
        opts={SAFE_OPTS}
        current={safe}
        onPick={pickSafe}
      />

      {/* Live preview frame: a dashed outline showing the current safe area. */}
      <section>
        <h2 className="mb-[1rem] text-[1.6rem] font-bold text-[var(--text-high)]">{m.settings.preview}</h2>
        <div className="relative h-[14rem] w-full overflow-hidden rounded-[var(--radius-lg)] bg-[var(--surface-1)]">
          <div className="absolute inset-0 border-2 border-dashed border-[var(--teal)]/50" style={{ margin: "var(--safe-y) var(--safe-x)" }}>
            <div className="flex h-full items-center justify-center">
              <span className="text-[1.4rem] font-semibold text-[var(--text-medium)]">
                {m.settings.safeZone}
              </span>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
