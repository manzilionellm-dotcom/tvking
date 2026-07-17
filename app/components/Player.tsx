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
 *
 * On touch screens the player behaves like the native video apps:
 * - tap the picture to show/hide the controls (they auto-hide after 3 s),
 * - double-tap the left/right half to skip ±10 s (with a visual flash and a
 *   subtle haptic tick where the platform supports it),
 * - the timeline is a real slider — drag anywhere to scrub.
 */

const DURATION = 40; // seconds (mock)
const UPNEXT_AT = 30; // show Up Next in the last 10s
const UI_HIDE_MS = 3000;
const DOUBLE_TAP_MS = 300;

function fmt(s: number) {
  const m = Math.floor(s / 60);
  const r = Math.floor(s % 60);
  return `${m}:${r.toString().padStart(2, "0")}`;
}

function buzz() {
  try {
    navigator.vibrate?.(10);
  } catch {
    /* haptics are best-effort */
  }
}

export default function Player({ item, next }: { item: MediaItem; next: MediaItem | null }) {
  const router = useRouter();
  const [pos, setPos] = useState(item.progress ? Math.floor(item.progress * DURATION) : 0);
  const [playing, setPlaying] = useState(true);
  const [autoCancelled, setAutoCancelled] = useState(false);
  const [uiVisible, setUiVisible] = useState(true);
  const [wakeStamp, setWakeStamp] = useState(0);
  const [flash, setFlash] = useState<{ dir: -1 | 1; id: number } | null>(null);
  const reduceRef = useRef(false);
  const navigatedRef = useRef(false);
  const touchUIRef = useRef(false);
  const tapRef = useRef<{ t: number; timer: number } | null>(null);
  const scrubbingRef = useRef(false);

  useEffect(() => {
    reduceRef.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    touchUIRef.current = window.matchMedia("(hover: none)").matches;
  }, []);

  /* Any interaction re-arms the auto-hide countdown. */
  const poke = useCallback(() => {
    setUiVisible(true);
    setWakeStamp((s) => s + 1);
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

  // Touch UI: controls fade out while playing, 3 s after the last interaction.
  useEffect(() => {
    if (!touchUIRef.current || !playing || atEnd || !uiVisible) return;
    const t = setTimeout(() => setUiVisible(false), UI_HIDE_MS);
    return () => clearTimeout(t);
  }, [playing, atEnd, uiVisible, wakeStamp]);

  // Never leave the viewer stranded on a bare frame once playback ends.
  useEffect(() => {
    if (atEnd) setUiVisible(true);
  }, [atEnd]);

  // The ±10 s flash burns itself out.
  useEffect(() => {
    if (!flash) return;
    const t = setTimeout(() => setFlash(null), 600);
    return () => clearTimeout(t);
  }, [flash]);

  const toggle = useCallback(() => {
    setPlaying((p) => !p);
    poke();
  }, [poke]);

  const seekBy = useCallback(
    (delta: number) => {
      setPos((p) => Math.max(0, Math.min(DURATION, p + delta)));
      poke();
    },
    [poke]
  );

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

  /*
   * Picture-surface taps. Touch: single tap toggles the controls, double-tap
   * skips ±10 s on the tapped half. Pointer (desktop): a click toggles play.
   */
  function onSurfaceClick(e: React.MouseEvent<HTMLDivElement>) {
    if (!touchUIRef.current) {
      toggle();
      return;
    }
    const now = Date.now();
    if (tapRef.current && now - tapRef.current.t < DOUBLE_TAP_MS) {
      window.clearTimeout(tapRef.current.timer);
      tapRef.current = null;
      const dir: -1 | 1 = e.clientX < window.innerWidth / 2 ? -1 : 1;
      seekBy(dir * 10);
      setFlash({ dir, id: now });
      buzz();
      return;
    }
    const timer = window.setTimeout(() => {
      tapRef.current = null;
      setUiVisible((v) => !v);
      setWakeStamp((s) => s + 1);
    }, DOUBLE_TAP_MS - 40);
    tapRef.current = { t: now, timer };
  }

  /* Draggable timeline (mouse + finger, via pointer capture). */
  function scrubTo(e: React.PointerEvent<HTMLDivElement>) {
    const r = e.currentTarget.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    setPos(Math.round(ratio * DURATION));
  }
  function onScrubStart(e: React.PointerEvent<HTMLDivElement>) {
    scrubbingRef.current = true;
    e.currentTarget.setPointerCapture(e.pointerId);
    scrubTo(e);
    poke();
  }
  function onScrubMove(e: React.PointerEvent<HTMLDivElement>) {
    if (!scrubbingRef.current) return;
    scrubTo(e);
    poke();
  }
  function onScrubEnd() {
    scrubbingRef.current = false;
  }

  const showUpNext = next && pos >= UPNEXT_AT && !autoCancelled;
  const countdown = Math.max(0, DURATION - pos);
  const pct = `${(pos / DURATION) * 100}%`;
  const uiClass = uiVisible ? "opacity-100" : "pointer-events-none opacity-0";

  return (
    <div className="fixed inset-0 z-[60] overflow-hidden bg-black">
      {/* "Video" surface */}
      <div
        className="absolute inset-0"
        style={{ background: `linear-gradient(120deg, ${item.art.from}, ${item.art.to})` }}
      />
      <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-transparent to-black/40" />

      {/* Tap layer — everything interactive sits above it. */}
      <div className="absolute inset-0" role="presentation" onClick={onSurfaceClick} />

      {/* ±10 s double-tap flash */}
      {flash && (
        <div
          key={flash.id}
          className={`seek-flash pointer-events-none absolute top-1/2 -translate-y-1/2 rounded-full bg-black/55 px-[1.3rem] py-[0.9rem] text-[1.15rem] font-bold text-white backdrop-blur ${
            flash.dir < 0 ? "left-[9%]" : "right-[9%]"
          }`}
        >
          {flash.dir < 0 ? "⟲ −10 s" : "+10 s ⟳"}
        </div>
      )}

      {/* Title (top) */}
      <div
        className={`absolute left-[var(--safe-x)] right-[var(--safe-x)] top-[var(--safe-y)] transition-opacity duration-300 ${uiClass}`}
      >
        <p className="text-[1.05rem] font-semibold uppercase tracking-[0.2em] text-[var(--gold)]">
          {item.live === "live" ? "● En direct" : "Lecture"}
        </p>
        <h1 className="font-display text-[2.6rem] font-extrabold tracking-tight text-white [text-shadow:0_0.2rem_1rem_rgba(0,0,0,0.6)] max-md:text-[1.5rem]">
          {item.title}
        </h1>
      </div>

      {/* Up Next panel — a sheet above the transport on hand-held screens. */}
      {showUpNext && (
        <div className="absolute bottom-[7rem] right-[var(--safe-x)] w-[24rem] rounded-[var(--radius-lg)] bg-[var(--surface-2)]/95 p-[1.2rem] shadow-2xl backdrop-blur max-md:bottom-[9.6rem] max-md:left-[var(--safe-x)] max-md:w-auto">
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
              className="h-full transition-all duration-1000 ease-linear"
              style={{ width: `${((10 - countdown) / 10) * 100}%`, background: "var(--gold-grad)" }}
            />
          </div>
          <div className="mt-[0.9rem] flex gap-[0.7rem]">
            <Link
              href={`/watch/${next!.id}`}
              data-focusable
              className="focusable flex-1 rounded-[var(--radius)] px-[1rem] py-[0.6rem] text-center text-[1.1rem] font-bold text-black"
              style={{ background: "var(--gold-grad)" }}
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
      <div
        className={`absolute inset-x-0 bottom-0 px-[var(--safe-x)] pb-[var(--safe-y)] pt-[3rem] transition-opacity duration-300 max-md:pb-[max(1.1rem,env(safe-area-inset-bottom))] ${uiClass}`}
      >
        <div className="mb-[0.8rem] flex items-center gap-[1rem]">
          <span className="text-[1rem] tabular-nums text-[var(--text-medium)]">{fmt(pos)}</span>
          {/* Scrubbable timeline: drag (or click) anywhere on the track. */}
          <div
            role="slider"
            aria-label="Position de lecture"
            aria-valuemin={0}
            aria-valuemax={DURATION}
            aria-valuenow={pos}
            onPointerDown={onScrubStart}
            onPointerMove={onScrubMove}
            onPointerUp={onScrubEnd}
            onPointerCancel={onScrubEnd}
            className="group/scrub relative -my-[0.6rem] flex-1 cursor-pointer touch-none py-[0.6rem]"
          >
            <div className="h-[0.4rem] overflow-hidden rounded-full bg-white/20">
              <div className="h-full" style={{ width: pct, background: "var(--gold-grad)" }} />
            </div>
            <div
              className="absolute top-1/2 h-[0.95rem] w-[0.95rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[var(--gold-strong)] shadow-[0_0_0.6rem_rgba(0,0,0,0.6)] opacity-0 transition-opacity group-hover/scrub:opacity-100 max-md:opacity-100"
              style={{ left: pct }}
            />
          </div>
          <span className="text-[1rem] tabular-nums text-[var(--text-medium)]">
            {item.live === "live" ? "DIRECT" : fmt(DURATION)}
          </span>
        </div>

        <div className="flex items-center gap-[1rem] max-md:gap-[0.7rem]">
          <button
            data-focusable
            onClick={() => seekBy(-10)}
            className="focusable rounded-full bg-white/12 px-[1rem] py-[0.6rem] text-[1.1rem] font-semibold text-white max-md:py-[0.75rem]"
            aria-label="Reculer de 10 secondes"
          >
            ⟲ 10s
          </button>
          <button
            data-focusable
            onClick={toggle}
            className="focusable flex h-[3.4rem] w-[3.4rem] items-center justify-center rounded-full text-black"
            style={{ background: "var(--gold-grad)" }}
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
            onClick={() => seekBy(10)}
            className="focusable rounded-full bg-white/12 px-[1rem] py-[0.6rem] text-[1.1rem] font-semibold text-white max-md:py-[0.75rem]"
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
