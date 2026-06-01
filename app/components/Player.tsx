"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import type { MediaItem } from "../lib/data";

/*
 * Mock player. The transport and the "À suivre" (Up Next) panel implement the
 * documented engagement pattern — autoplay of the next item with a visible
 * countdown — but with explicit user control (cancel / play now), per NN/g
 * guidance that video is only useful when the user stays in control, and the
 * critique that a too-short auto-advance is a dark pattern. Auto-advance is
 * disabled when the user prefers reduced motion.
 */

const DURATION = 40; // seconds (mock)
const UPNEXT_AT = 30; // show Up Next in the last 10s

function fmt(s: number) {
  const m = Math.floor(s / 60);
  const r = Math.floor(s % 60);
  return `${m}:${r.toString().padStart(2, "0")}`;
}

export default function Player({ item, next }: { item: MediaItem; next: MediaItem | null }) {
  const router = useRouter();
  const [pos, setPos] = useState(item.progress ? Math.floor(item.progress * DURATION) : 0);
  const [playing, setPlaying] = useState(true);
  const [autoCancelled, setAutoCancelled] = useState(false);
  const reduceRef = useRef(false);
  const navigatedRef = useRef(false);

  useEffect(() => {
    reduceRef.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }, []);

  // Advance the mock playhead one tick at a time; stops itself at the end.
  useEffect(() => {
    if (!playing || pos >= DURATION) return;
    const t = setTimeout(() => setPos((p) => Math.min(p + 1, DURATION)), 1000);
    return () => clearTimeout(t);
  }, [playing, pos]);

  // At the end, auto-advance to the next item unless cancelled / reduced-motion.
  useEffect(() => {
    if (pos < DURATION || navigatedRef.current) return;
    if (next && !autoCancelled && !reduceRef.current) {
      navigatedRef.current = true;
      router.push(`/watch/${next.id}`);
    }
  }, [pos, next, autoCancelled, router]);

  const atEnd = pos >= DURATION;

  const toggle = useCallback(() => setPlaying((p) => !p), []);

  // Space / Enter toggles play (k is the YouTube convention).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.key === " " || e.key === "k") && document.activeElement === document.body) {
        e.preventDefault();
        toggle();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggle]);

  const showUpNext = next && pos >= UPNEXT_AT && !autoCancelled;
  const countdown = Math.max(0, DURATION - pos);

  return (
    <div className="fixed inset-0 z-[60] overflow-hidden bg-black">
      {/* "Video" surface */}
      <div
        className="absolute inset-0"
        style={{ background: `linear-gradient(120deg, ${item.art.from}, ${item.art.to})` }}
      />
      <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-transparent to-black/40" />

      {/* Title (top) */}
      <div className="absolute left-[var(--safe-x)] top-[var(--safe-y)] right-[var(--safe-x)]">
        <p className="text-[1.05rem] font-semibold uppercase tracking-[0.2em] text-[var(--gold)]">
          {item.live === "live" ? "● En direct" : "Lecture"}
        </p>
        <h1 className="text-[2.4rem] font-extrabold tracking-tight text-white">{item.title}</h1>
      </div>

      {/* Up Next panel */}
      {showUpNext && (
        <div className="absolute bottom-[7rem] right-[var(--safe-x)] w-[24rem] rounded-[var(--radius-lg)] bg-[var(--surface-2)]/95 p-[1.2rem] shadow-2xl backdrop-blur">
          <p className="mb-[0.6rem] text-[1rem] font-semibold uppercase tracking-wider text-[var(--text-medium)]">
            À suivre · dans {countdown}s
          </p>
          <div className="flex gap-[0.9rem]">
            <div
              className="h-[4.5rem] w-[8rem] shrink-0 rounded-[var(--radius)]"
              style={{ background: `linear-gradient(140deg, ${next!.art.from}, ${next!.art.to})` }}
            />
            <div className="min-w-0">
              <h3 className="truncate text-[1.2rem] font-bold text-[var(--text-high)]">{next!.title}</h3>
              {next!.league && (
                <p className="truncate text-[1rem] text-[var(--text-medium)]">{next!.league}</p>
              )}
            </div>
          </div>
          {/* Countdown fill — the visible "color wipe". */}
          <div className="mt-[0.8rem] h-[0.3rem] overflow-hidden rounded-full bg-white/20">
            <div
              className="h-full bg-[var(--gold)] transition-all duration-1000 ease-linear"
              style={{ width: `${((10 - countdown) / 10) * 100}%` }}
            />
          </div>
          <div className="mt-[0.9rem] flex gap-[0.7rem]">
            <Link
              href={`/watch/${next!.id}`}
              data-focusable
              className="focusable flex-1 rounded-[var(--radius)] bg-[var(--gold)] px-[1rem] py-[0.6rem] text-center text-[1.1rem] font-bold text-black"
            >
              Lire maintenant
            </Link>
            <button
              data-focusable
              onClick={() => setAutoCancelled(true)}
              className="focusable rounded-[var(--radius)] bg-white/15 px-[1rem] py-[0.6rem] text-[1.1rem] font-semibold text-[var(--text-high)]"
            >
              Annuler
            </button>
          </div>
        </div>
      )}

      {/* Transport bar */}
      <div className="absolute inset-x-0 bottom-0 px-[var(--safe-x)] pb-[var(--safe-y)] pt-[3rem]">
        <div className="mb-[0.8rem] flex items-center gap-[1rem]">
          <span className="text-[1rem] tabular-nums text-[var(--text-medium)]">{fmt(pos)}</span>
          <div className="h-[0.4rem] flex-1 overflow-hidden rounded-full bg-white/20">
            <div className="h-full bg-[var(--gold)]" style={{ width: `${(pos / DURATION) * 100}%` }} />
          </div>
          <span className="text-[1rem] tabular-nums text-[var(--text-medium)]">
            {item.live === "live" ? "DIRECT" : fmt(DURATION)}
          </span>
        </div>

        <div className="flex items-center gap-[1rem]">
          <button
            data-focusable
            onClick={() => setPos((p) => Math.max(0, p - 10))}
            className="focusable rounded-full bg-white/12 px-[1rem] py-[0.6rem] text-[1.1rem] font-semibold text-white"
            aria-label="Reculer de 10 secondes"
          >
            ⟲ 10s
          </button>
          <button
            data-focusable
            onClick={toggle}
            className="focusable flex h-[3.4rem] w-[3.4rem] items-center justify-center rounded-full bg-[var(--gold)] text-black"
            aria-label={playing && !atEnd ? "Pause" : "Lecture"}
          >
            {playing && !atEnd ? (
              <svg className="h-[1.5rem] w-[1.5rem]" viewBox="0 0 24 24" fill="currentColor">
                <path d="M6 5h4v14H6zM14 5h4v14h-4z" />
              </svg>
            ) : (
              <svg className="h-[1.5rem] w-[1.5rem]" viewBox="0 0 24 24" fill="currentColor">
                <path d="M8 5v14l11-7z" />
              </svg>
            )}
          </button>
          <button
            data-focusable
            onClick={() => setPos((p) => Math.min(DURATION, p + 10))}
            className="focusable rounded-full bg-white/12 px-[1rem] py-[0.6rem] text-[1.1rem] font-semibold text-white"
            aria-label="Avancer de 10 secondes"
          >
            10s ⟳
          </button>
          <Link
            href={`/title/${item.id}`}
            data-focusable
            className="focusable ml-auto rounded-[var(--radius)] bg-white/12 px-[1.3rem] py-[0.7rem] text-[1.1rem] font-semibold text-white"
          >
            ✕ Quitter
          </Link>
        </div>
      </div>
    </div>
  );
}
