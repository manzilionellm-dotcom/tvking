import Link from "next/link";
import type { MediaItem } from "../lib/data";
import { LevelBadge, LiveBadge } from "./Badge";
import { ReminderFlag } from "./CollectionButton";

/* Card widths per shape. 16:9 is the default video card; 1:1 for logos/topics;
   2:3 for course "posters" — the three Android TV card aspect ratios. */
const SHAPE = {
  "16:9": { w: "20rem", aspect: "16 / 9" },
  "1:1": { w: "11rem", aspect: "1 / 1" },
  "2:3": { w: "13rem", aspect: "2 / 3" },
} as const;

export default function MediaCard({ item }: { item: MediaItem }) {
  const shape = item.shape ?? "16:9";
  const dims = SHAPE[shape];

  return (
    <Link
      href={item.href ?? `/title/${item.id}`}
      data-focusable
      data-focus-key={`card:${item.id}`}
      className="card focusable group relative block shrink-0 cursor-pointer text-left"
      style={{ width: dims.w }}
      aria-label={item.title}
    >
      {/* Artwork — gradient stands in for poster art (no binary assets needed). */}
      <div
        className="relative w-full overflow-hidden rounded-[var(--radius)] ring-1 ring-[var(--hairline)] transition-shadow group-focus-visible:ring-[rgba(244,213,141,0.6)]"
        style={{
          aspectRatio: dims.aspect,
          background: `linear-gradient(140deg, ${item.art.from}, ${item.art.to})`,
        }}
      >
        {/* Subtle top sheen for a premium, lit feel. */}
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-white/12 to-transparent opacity-60" />

        {/* Top-row badges: LIVE / replay / upcoming. */}
        {item.live && (
          <div className="absolute left-[0.6rem] top-[0.6rem]">
            <LiveBadge state={item.live} />
          </div>
        )}
        {item.badge && !item.live && (
          <div
            className="absolute left-[0.6rem] top-[0.6rem] rounded-md px-[0.5rem] py-[0.15rem] text-[0.75rem] font-bold uppercase tracking-wider text-black"
            style={{ background: "var(--gold-grad)" }}
          >
            {item.badge}
          </div>
        )}

        {/* "Rappel activé" — the third state of the sport tri-state model. */}
        {item.live === "upcoming" && <ReminderFlag id={item.id} />}

        {/* Live clock + score overlay (bottom). */}
        {(item.clock || item.score) && (
          <div className="absolute inset-x-0 bottom-0 flex items-center justify-between gap-2 bg-gradient-to-t from-black/80 to-transparent px-[0.6rem] pb-[0.5rem] pt-[1.5rem]">
            {item.score && (
              <span className="text-[1rem] font-bold tabular-nums text-white">{item.score}</span>
            )}
            {item.clock && (
              <span className="text-[0.85rem] font-semibold text-[var(--live)]">{item.clock}</span>
            )}
          </div>
        )}

        {/* Centred label for logo/topic (1:1) cards. */}
        {shape === "1:1" && (
          <div className="absolute inset-0 flex items-center justify-center p-2 text-center text-[1.05rem] font-bold text-white">
            {item.title}
          </div>
        )}

        {/* Resume progress bar (Continue Watching). */}
        {item.progress !== undefined && (
          <div className="absolute inset-x-0 bottom-0 h-[0.35rem] bg-black/50">
            <div
              className="h-full"
              style={{ width: `${Math.round(item.progress * 100)}%`, background: "var(--gold-grad)" }}
            />
          </div>
        )}
      </div>

      {/* Meta block — width matches the thumbnail (Android TV content block). */}
      {shape !== "1:1" && (
        <div className="mt-[0.6rem] px-[0.1rem]">
          <h3 className="truncate text-[1.05rem] font-semibold text-[var(--text-high)]">
            {item.title}
          </h3>
          <div className="card-meta mt-[0.2rem] flex items-center gap-[0.5rem] text-[0.85rem] text-[var(--text-medium)] opacity-80">
            {item.level && <LevelBadge level={item.level} />}
            {item.duration && <span>{item.duration}</span>}
            {item.lessons && <span>{item.lessons} leçons</span>}
            {item.startsIn && <span>{item.startsIn}</span>}
            {item.league && <span className="truncate">{item.league}</span>}
            {item.instructor && <span className="truncate">{item.instructor}</span>}
            {item.subtitle && !item.level && <span className="truncate">{item.subtitle}</span>}
          </div>
        </div>
      )}
    </Link>
  );
}
