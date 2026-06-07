// =========================================================
//  Badge.tsx — Pastilles d'état (LIVE / à venir / replay) et niveau
// =========================================================
//  Deux familles :
//    - LiveBadge : état temporel d'un contenu.
//    - LevelBadge : niveau pédagogique d'un cours.
//  Couleurs désaturées (le rouge LIVE est adouci, cf. design system).
// =========================================================

import type { BadgeKind, Level } from "../lib/data";

const LIVE_STYLES: Record<
  Exclude<BadgeKind, "none">,
  { label: string; bg: string; fg: string; dot?: boolean }
> = {
  live: { label: "EN DIRECT", bg: "var(--live)", fg: "#fff", dot: true },
  upcoming: { label: "À VENIR", bg: "var(--surface-3)", fg: "var(--text-high)" },
  replay: { label: "REPLAY", bg: "var(--surface-3)", fg: "var(--text-medium)" },
  new: { label: "NOUVEAU", bg: "var(--gold-deep)", fg: "#1a1300" },
};

export function LiveBadge({ kind }: { kind: BadgeKind }) {
  if (!kind || kind === "none") return null;
  const s = LIVE_STYLES[kind];
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "0.4em",
        padding: "0.25em 0.6em",
        borderRadius: "999px",
        fontSize: "0.78rem",
        fontWeight: 800,
        letterSpacing: "0.06em",
        background: s.bg,
        color: s.fg,
        lineHeight: 1,
      }}
    >
      {s.dot && (
        <span
          aria-hidden
          style={{
            width: "0.55em",
            height: "0.55em",
            borderRadius: "999px",
            background: "#fff",
            // Le point « pulse » signale le direct ; coupé en reduced-motion.
            animation: "tvk-pulse 1.6s ease-in-out infinite",
          }}
        />
      )}
      {s.label}
    </span>
  );
}

const LEVEL_LABELS: Record<Level, string> = {
  debutant: "Débutant",
  intermediaire: "Intermédiaire",
  avance: "Avancé",
};

export function LevelBadge({ level }: { level: Level }) {
  return (
    <span
      style={{
        display: "inline-flex",
        padding: "0.2em 0.55em",
        borderRadius: "0.4rem",
        fontSize: "0.74rem",
        fontWeight: 700,
        background: "rgba(255,255,255,0.08)",
        color: "var(--text-medium)",
        border: "1px solid rgba(255,255,255,0.12)",
      }}
    >
      {LEVEL_LABELS[level]}
    </span>
  );
}
