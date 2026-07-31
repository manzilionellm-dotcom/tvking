"use client";

import Link from "next/link";
import { useEffect, useState, useSyncExternalStore } from "react";
import type { MediaItem } from "../lib/data";
import { isDownloaded, loadDownloads, saveDownloads, withDownloaded } from "../lib/downloads";

/*
 * Film playback actions — the zero-attente path.
 *
 * A film downloads itself to the device as soon as its page opens ("les films
 * se téléchargent directement"). While it does, the user sees a determinate
 * progress bar — a percentage that only moves forward, never a spinner. Once
 * ready (persisted across sessions), the only button is « Lecture instantanée »:
 * playback starts immediately, nothing can buffer.
 */

/** Simulated download pace: 0→100 % in ~2 s, in visible determinate steps. */
const STEP = 4;
const STEP_MS = 70;

/* The downloads store only changes through this component, never underneath it. */
const noSubscription = () => () => {};

export default function FilmActions({ item }: { item: MediaItem }) {
  // Hydration-safe: the server snapshot says "not downloaded" (the static page
  // shows the download starting); the client corrects right after mount.
  const alreadyDone = useSyncExternalStore(
    noSubscription,
    () => isDownloaded(loadDownloads(), item.id),
    () => false
  );
  const [progress, setProgress] = useState(0);
  const done = alreadyDone || progress >= 100;

  // Auto-download on arrival — determinate steps, stops itself at 100 %.
  useEffect(() => {
    if (done) return;
    const t = setInterval(() => setProgress((p) => Math.min(100, p + STEP)), STEP_MS);
    return () => clearInterval(t);
  }, [done]);

  // Persist completion once, so the film stays instant on every next visit.
  useEffect(() => {
    if (progress >= 100 && !alreadyDone) {
      saveDownloads(withDownloaded(loadDownloads(), item.id, Date.now()));
    }
  }, [progress, alreadyDone, item.id]);

  if (!done) {
    return (
      <div className="w-full max-w-[30rem]">
        <div className="mb-[0.5rem] flex items-baseline justify-between">
          <span className="text-[1.15rem] font-semibold text-[var(--text-high)]">
            Téléchargement du film…
          </span>
          <span className="text-[1.3rem] font-bold tabular-nums text-[var(--gold)]">{progress} %</span>
        </div>
        {/* Determinate bar — the promised "jamais de roue qui tourne". */}
        <div
          role="progressbar"
          aria-valuenow={progress}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label="Téléchargement du film"
          className="h-[0.5rem] w-full overflow-hidden rounded-full bg-white/15"
        >
          <div
            className="h-full rounded-full transition-[width] duration-100 ease-linear"
            style={{ width: `${progress}%`, background: "var(--gold-grad)" }}
          />
        </div>
        <p className="mt-[0.5rem] text-[1rem] text-[var(--text-medium)]">
          Le film sera lu depuis l&apos;appareil : démarrage immédiat, aucune mise en mémoire tampon.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-[1rem]">
      <Link
        href={`/watch/${item.id}`}
        data-focusable
        data-focus-default
        className="focusable flex items-center gap-[0.6rem] rounded-[var(--radius)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black shadow-[0_0.6rem_1.6rem_rgba(227,185,107,0.35)]"
        style={{ background: "var(--gold-grad)" }}
      >
        <svg className="h-[1.3rem] w-[1.3rem]" viewBox="0 0 24 24" fill="currentColor">
          <path d="M8 5v14l11-7z" />
        </svg>
        Lecture instantanée
      </Link>
      <span className="inline-flex items-center gap-[0.4rem] rounded-md bg-[var(--sport)]/15 px-[0.8rem] py-[0.35rem] text-[1rem] font-bold text-[var(--sport)]">
        ✓ Téléchargé sur l&apos;appareil
      </span>
    </div>
  );
}
