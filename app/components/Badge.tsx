import type { LiveState, MediaItem } from "../lib/data";

/** Pulsing red LIVE badge — the documented sports convention. */
export function LiveBadge({ state }: { state: LiveState }) {
  if (state === "live") {
    return (
      <span className="inline-flex items-center gap-[0.4rem] rounded-md bg-[var(--live)] px-[0.6rem] py-[0.2rem] text-[0.85rem] font-bold uppercase tracking-wider text-white">
        <span className="relative flex h-[0.55rem] w-[0.55rem]">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-white/80" />
          <span className="relative inline-flex h-[0.55rem] w-[0.55rem] rounded-full bg-white" />
        </span>
        Direct
      </span>
    );
  }
  if (state === "upcoming") {
    return (
      <span className="rounded-md bg-white/15 px-[0.6rem] py-[0.2rem] text-[0.85rem] font-semibold uppercase tracking-wider text-[var(--text-high)]">
        À venir
      </span>
    );
  }
  return (
    <span className="rounded-md bg-white/10 px-[0.6rem] py-[0.2rem] text-[0.85rem] font-semibold uppercase tracking-wider text-[var(--text-medium)]">
      Replay
    </span>
  );
}

const LEVEL_COLOR: Record<NonNullable<MediaItem["level"]>, string> = {
  Débutant: "var(--sport)",
  Intermédiaire: "var(--gold)",
  Avancé: "var(--learn)",
};

/** Skill-level chip — the documented first-class facet for learning content. */
export function LevelBadge({ level }: { level: NonNullable<MediaItem["level"]> }) {
  return (
    <span
      className="rounded-md px-[0.55rem] py-[0.15rem] text-[0.8rem] font-semibold"
      style={{ color: LEVEL_COLOR[level], background: "rgba(255,255,255,0.08)" }}
    >
      {level}
    </span>
  );
}
