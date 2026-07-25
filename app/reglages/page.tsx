"use client";

import { useSyncExternalStore } from "react";
import { PREFS, applyComfort } from "../components/Preferences";

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
function readPref(key: string, fallback = "1") {
  return typeof window === "undefined" ? fallback : localStorage.getItem(key) ?? fallback;
}
function writePref(key: string, cssVar: string, value: string) {
  localStorage.setItem(key, value);
  document.documentElement.style.setProperty(cssVar, value);
  listeners.forEach((l) => l());
}
function usePref(key: string, fallback = "1") {
  return useSyncExternalStore(subscribe, () => readPref(key, fallback), () => fallback);
}

/** Comfort is a named level, not a scale: it drives two CSS variables at once. */
function writeComfort(value: string) {
  localStorage.setItem(PREFS.comfort, value);
  applyComfort(value);
  listeners.forEach((l) => l());
}

/*
 * Réglages — lets the viewer adapt the UI to their own television and seating:
 * - Taille du texte: scales the rem base (legibility at distance).
 * - Marge de sécurité: compensates for TV overscan that crops screen edges
 *   (the tvOS overscanCompensationInsets / Android overscan problem).
 * Both persist to localStorage and apply live via CSS variables.
 */

type Opt = { label: string; value: string; hint: string };

const TEXT_OPTS: Opt[] = [
  { label: "Compact", value: "0.9", hint: "Plus de contenu" },
  { label: "Standard", value: "1", hint: "Recommandé" },
  { label: "Grand", value: "1.15", hint: "Lecture facile" },
  { label: "Très grand", value: "1.3", hint: "Vision réduite" },
];

const COMFORT_OPTS: Opt[] = [
  { label: "Désactivé", value: "off", hint: "Image d'origine" },
  { label: "Doux", value: "doux", hint: "Soirée, lumière tamisée" },
  { label: "Nuit", value: "nuit", hint: "Pièce sombre, moins de bleu" },
];

const SAFE_OPTS: Opt[] = [
  { label: "Faible", value: "0.6", hint: "Écran sans surbalayage" },
  { label: "Standard", value: "1", hint: "Recommandé (5%)" },
  { label: "Élevée", value: "1.4", hint: "Bords rognés" },
];

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
  const ui = usePref(PREFS.uiScale);
  const safe = usePref(PREFS.safeScale);
  const comfort = usePref(PREFS.comfort, "off");

  const pickUi = (v: string) => writePref(PREFS.uiScale, "--ui-scale", v);
  const pickSafe = (v: string) => writePref(PREFS.safeScale, "--safe-scale", v);

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Réglages d&apos;affichage
      </h1>
      <p className="mb-[2.2rem] text-[1.3rem] text-[var(--text-medium)]">
        Adaptez l&apos;application à votre téléviseur et à votre distance de visionnage.
      </p>

      <Group
        title="Taille du texte"
        desc="Le texte est conçu pour être lisible à ~3 m. Agrandissez-le si besoin."
        opts={TEXT_OPTS}
        current={ui}
        onPick={pickUi}
      />
      <Group
        title="Marge de sécurité (overscan)"
        desc="Si les bords de l'image sont rognés par votre TV, augmentez la marge."
        opts={SAFE_OPTS}
        current={safe}
        onPick={pickSafe}
      />

      <Group
        title="Confort visuel"
        desc="En pièce sombre, un écran moins lumineux et un blanc plus chaud fatiguent moins les yeux (moins de lumière bleue)."
        opts={COMFORT_OPTS}
        current={comfort}
        onPick={writeComfort}
      />

      {/* Live preview frame: a dashed outline showing the current safe area. */}
      <section>
        <h2 className="mb-[1rem] text-[1.6rem] font-bold text-[var(--text-high)]">Aperçu</h2>
        <div className="relative h-[14rem] w-full overflow-hidden rounded-[var(--radius-lg)] bg-[var(--surface-1)]">
          <div className="absolute inset-0 border-2 border-dashed border-[var(--teal)]/50" style={{ margin: "var(--safe-y) var(--safe-x)" }}>
            <div className="flex h-full items-center justify-center">
              <span className="text-[1.4rem] font-semibold text-[var(--text-medium)]">
                Zone de sécurité — tout le contenu reste à l&apos;intérieur
              </span>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
