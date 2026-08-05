"use client";

import { useRouter } from "next/navigation";
import { useEffect, useSyncExternalStore } from "react";
import { getItem } from "../lib/data";
import { getMini, getMiniServer, setMini, subscribeMini, updateMini } from "../lib/mini";
import { loadResume, saveResume, withPosition } from "../lib/resume";

/*
 * Floating mini-player (YouTube convention, cf. the reference screenshot):
 * a small video window pinned bottom-right that keeps playing while the user
 * browses. Every control lives in the little window itself — écouteurs
 * (audio-only), play/pause, up-next, expand, close.
 */

const DURATION = 40; // seconds — same mock duration as the full player

export default function MiniPlayer() {
  const router = useRouter();
  const mini = useSyncExternalStore(subscribeMini, getMini, getMiniServer);
  /* Live channels have no duration: the mini clock keeps counting, nothing
     ends, and nothing enters the resume store. */
  const isLive = mini?.item.live === "live";

  // Advance the mock playhead one tick at a time while playing.
  useEffect(() => {
    if (!mini || !mini.playing || (!isLive && mini.pos >= DURATION)) return;
    const t = setTimeout(
      () => updateMini({ pos: isLive ? mini.pos + 1 : Math.min(mini.pos + 1, DURATION) }),
      1000
    );
    return () => clearTimeout(t);
  }, [mini, isLive]);

  // Persist the playhead every 5s and at the end (finished → entry dropped),
  // exactly like the full player, so "Reprendre" stays coherent.
  useEffect(() => {
    if (!mini || isLive || mini.pos === 0 || (mini.pos % 5 !== 0 && mini.pos < DURATION)) return;
    saveResume(withPosition(loadResume(), mini.item.id, mini.pos, DURATION, Date.now()));
  }, [mini, isLive]);

  // At the end: chain to the next item if there is one, otherwise close.
  useEffect(() => {
    if (!mini || isLive || mini.pos < DURATION) return;
    if (mini.next) {
      setMini({ item: mini.next, next: null, pos: 0, playing: true, audioOnly: mini.audioOnly });
    } else {
      setMini(null);
    }
  }, [mini, isLive]);

  if (!mini) return null;
  const { item, next, pos, playing, audioOnly } = mini;

  const expand = () => {
    // Hand the playhead to the full player through the resume store.
    if (!isLive) saveResume(withPosition(loadResume(), item.id, pos, DURATION, Date.now()));
    setMini(null);
    // Catalog items have a /watch page; IPTV channels reopen on the TV page.
    router.push(getItem(item.id) ? `/watch/${item.id}` : "/tv");
  };

  const btn =
    "focusable flex h-[2.4rem] w-[2.4rem] items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm";

  return (
    <div
      role="complementary"
      aria-label={`Lecture réduite : ${item.title}`}
      className="fixed bottom-[1rem] right-[1rem] z-[70] w-[19rem] overflow-hidden rounded-[var(--radius-lg)] shadow-2xl ring-1 ring-[var(--hairline)] max-md:bottom-[6.2rem]"
    >
      {/* "Video" surface — or the écouteurs (audio-only) card. */}
      <div
        className="relative aspect-video w-full"
        style={{
          background: audioOnly
            ? "var(--surface-2)"
            : `linear-gradient(120deg, ${item.art.from}, ${item.art.to})`,
        }}
      >
        {audioOnly && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-[0.4rem]">
            <svg className="h-[2.2rem] w-[2.2rem] text-[var(--gold)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M4 13a8 8 0 0 1 16 0" strokeLinecap="round" />
              <rect x="3" y="13" width="4" height="7" rx="1.5" />
              <rect x="17" y="13" width="4" height="7" rx="1.5" />
            </svg>
            <span className="text-[0.85rem] font-semibold uppercase tracking-wider text-[var(--text-medium)]">
              Audio seulement
            </span>
          </div>
        )}

        {/* Top row: expand + close (YouTube layout). */}
        <div className="absolute inset-x-[0.5rem] top-[0.5rem] flex justify-end gap-[0.5rem]">
          <button data-focusable onClick={expand} className={btn} aria-label="Agrandir">
            <svg className="h-[1.1rem] w-[1.1rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7" />
            </svg>
          </button>
          <button data-focusable onClick={() => setMini(null)} className={btn} aria-label="Fermer la lecture réduite">
            <svg className="h-[1.1rem] w-[1.1rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="m6 6 12 12M18 6 6 18" />
            </svg>
          </button>
        </div>

        {/* Bottom row: écouteurs · play/pause · up-next — all in the little video. */}
        <div className="absolute inset-x-[0.5rem] bottom-[0.5rem] flex items-center justify-between">
          <button
            data-focusable
            onClick={() => updateMini({ audioOnly: !audioOnly })}
            className={btn}
            style={audioOnly ? { background: "var(--gold-grad)", color: "#000" } : undefined}
            aria-label={audioOnly ? "Réafficher la vidéo" : "Écouter sans la vidéo"}
            aria-pressed={audioOnly}
          >
            <svg className="h-[1.15rem] w-[1.15rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M4 13a8 8 0 0 1 16 0" strokeLinecap="round" />
              <rect x="3" y="13" width="4" height="7" rx="1.5" />
              <rect x="17" y="13" width="4" height="7" rx="1.5" />
            </svg>
          </button>
          <button
            data-focusable
            onClick={() => updateMini({ playing: !playing })}
            className={btn}
            aria-label={playing ? "Pause" : "Lecture"}
          >
            {playing ? (
              <svg className="h-[1.15rem] w-[1.15rem]" viewBox="0 0 24 24" fill="currentColor">
                <path d="M6 5h4v14H6zM14 5h4v14h-4z" />
              </svg>
            ) : (
              <svg className="h-[1.15rem] w-[1.15rem]" viewBox="0 0 24 24" fill="currentColor">
                <path d="M8 5v14l11-7z" />
              </svg>
            )}
          </button>
          {next ? (
            <button
              data-focusable
              onClick={() =>
                setMini({ item: next, next: null, pos: 0, playing: true, audioOnly })
              }
              className={btn}
              aria-label={`Suivant : ${next.title}`}
            >
              <svg className="h-[1.15rem] w-[1.15rem]" viewBox="0 0 24 24" fill="currentColor">
                <path d="M6 5v14l9-7zM17 5h2v14h-2z" />
              </svg>
            </button>
          ) : (
            <span className="h-[2.4rem] w-[2.4rem]" aria-hidden />
          )}
        </div>
      </div>

      {/* Title + progress under the video. */}
      <div className="bg-[var(--surface-1)] px-[0.8rem] pb-[0.7rem] pt-[0.5rem]">
        <p className="truncate text-[0.95rem] font-semibold text-[var(--text-high)]">{item.title}</p>
        <div className="mt-[0.4rem] h-[0.25rem] overflow-hidden rounded-full bg-white/15">
          <div
            className="h-full"
            style={{
              width: `${isLive ? 100 : (pos / DURATION) * 100}%`,
              background: "var(--gold-grad)",
            }}
          />
        </div>
      </div>
    </div>
  );
}
