"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { MediaItem } from "../lib/data";
import { setMini } from "../lib/mini";
import { loadResume, positionOf, saveResume, withPosition } from "../lib/resume";

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

/* TV remotes surface "back" under several key names depending on the platform
   (Android TV WebView, Tizen, WebOS, desktop). All of them leave the player. */
const BACK_KEYS = new Set(["Escape", "Backspace", "GoBack", "BrowserBack", "XF86Back"]);

/* The resume store only changes through this player, never underneath it. */
const noSubscription = () => () => {};

function fmt(s: number) {
  const m = Math.floor(s / 60);
  const r = Math.floor(s % 60);
  return `${m}:${r.toString().padStart(2, "0")}`;
}

export default function Player({
  item,
  next,
  onExit,
}: {
  item: MediaItem;
  next: MediaItem | null;
  /** When set (IPTV channels), leaving the player calls this instead of
      navigating to a /title page — channels have no detail page. */
  onExit?: () => void;
}) {
  const router = useRouter();
  const [pos, setPos] = useState(item.progress ? Math.floor(item.progress * DURATION) : 0);
  const [playing, setPlaying] = useState(true);
  const [autoCancelled, setAutoCancelled] = useState(false);
  const reduceRef = useRef(false);
  const navigatedRef = useRef(false);

  useEffect(() => {
    reduceRef.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }, []);

  // The full-screen player owns playback: any floating mini-player is closed
  // on entry so two things never play at once.
  useEffect(() => {
    setMini(null);
  }, []);

  // A previously saved position wins over the mock progress hint. Read via
  // useSyncExternalStore (server snapshot: null) so hydration stays consistent,
  // then seeded exactly once as a render-phase state adjustment.
  const savedPos = useSyncExternalStore(
    noSubscription,
    () => positionOf(loadResume(), item.id),
    () => null
  );
  const [seeded, setSeeded] = useState(false);
  if (savedPos !== null && !seeded) {
    setSeeded(true);
    setPos(Math.min(Math.floor(savedPos), DURATION));
  }

  // Persist the playhead every 5s and at the end (where the entry is dropped —
  // a finished programme must not reappear in "Reprendre").
  useEffect(() => {
    if (pos === 0 || (pos % 5 !== 0 && pos < DURATION)) return;
    saveResume(withPosition(loadResume(), item.id, pos, DURATION, Date.now()));
  }, [pos, item.id]);

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
  const exit = useCallback(() => {
    if (onExit) onExit();
    else router.push(`/title/${item.id}`);
  }, [onExit, router, item.id]);

  // Minimise to the floating mini-player (YouTube pattern): playback — or
  // audio alone, via the écouteurs button — continues while the user browses.
  const minimize = useCallback(
    (audioOnly: boolean) => {
      saveResume(withPosition(loadResume(), item.id, pos, DURATION, Date.now()));
      setMini({ item, next, pos, playing, audioOnly });
      exit();
    },
    [item, next, pos, playing, exit]
  );

  // Remote-control keys: BACK leaves the player, media keys drive transport
  // directly (they work whatever element holds the focus). Space/k still
  // toggle when nothing is focused (YouTube convention).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (BACK_KEYS.has(e.key)) {
        e.preventDefault();
        exit();
        return;
      }
      switch (e.key) {
        case "MediaPlayPause":
          e.preventDefault();
          toggle();
          return;
        case "MediaPlay":
          e.preventDefault();
          setPlaying(true);
          return;
        case "MediaPause":
          e.preventDefault();
          setPlaying(false);
          return;
        case "MediaStop":
          e.preventDefault();
          exit();
          return;
        case "MediaRewind":
          e.preventDefault();
          setPos((p) => Math.max(0, p - 10));
          return;
        case "MediaFastForward":
          e.preventDefault();
          setPos((p) => Math.min(DURATION, p + 10));
          return;
      }
      if ((e.key === " " || e.key === "k") && document.activeElement === document.body) {
        e.preventDefault();
        toggle();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggle, exit]);

  const showUpNext = next && pos >= UPNEXT_AT && !autoCancelled;
  const countdown = Math.max(0, DURATION - pos);

  return (
    // data-focus-scope confines D-pad navigation to the player while it covers
    // the app — focus must never land on the sidebar hidden underneath.
    <div data-focus-scope className="fixed inset-0 z-[60] overflow-hidden bg-black">
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
        <h1 className="font-display text-[2.6rem] font-extrabold tracking-tight text-white [text-shadow:0_0.2rem_1rem_rgba(0,0,0,0.6)]">{item.title}</h1>
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
      <div className="absolute inset-x-0 bottom-0 px-[var(--safe-x)] pb-[var(--safe-y)] pt-[3rem]">
        <div className="mb-[0.8rem] flex items-center gap-[1rem]">
          <span className="text-[1rem] tabular-nums text-[var(--text-medium)]">{fmt(pos)}</span>
          <div className="h-[0.4rem] flex-1 overflow-hidden rounded-full bg-white/20">
            <div className="h-full" style={{ width: `${(pos / DURATION) * 100}%`, background: "var(--gold-grad)" }} />
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
            data-focus-default
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
            onClick={() => setPos((p) => Math.min(DURATION, p + 10))}
            className="focusable rounded-full bg-white/12 px-[1rem] py-[0.6rem] text-[1.1rem] font-semibold text-white"
            aria-label="Avancer de 10 secondes"
          >
            10s ⟳
          </button>
          {/* Écouteurs: keep the sound, drop the video — goes to the mini-player. */}
          <button
            data-focusable
            onClick={() => minimize(true)}
            className="focusable ml-auto flex items-center gap-[0.5rem] rounded-[var(--radius)] bg-white/12 px-[1.1rem] py-[0.7rem] text-[1.1rem] font-semibold text-white"
            aria-label="Écouter sans la vidéo"
          >
            <svg className="h-[1.2rem] w-[1.2rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M4 13a8 8 0 0 1 16 0" strokeLinecap="round" />
              <rect x="3" y="13" width="4" height="7" rx="1.5" />
              <rect x="17" y="13" width="4" height="7" rx="1.5" />
            </svg>
            Écouteurs
          </button>
          {/* Réduire: YouTube-style floating mini-player, video included. */}
          <button
            data-focusable
            onClick={() => minimize(false)}
            className="focusable flex items-center gap-[0.5rem] rounded-[var(--radius)] bg-white/12 px-[1.1rem] py-[0.7rem] text-[1.1rem] font-semibold text-white"
            aria-label="Réduire la vidéo"
          >
            <svg className="h-[1.2rem] w-[1.2rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M10 20H4v-6M20 4l-9 9M4 20l6-6" />
              <rect x="13" y="13" width="8" height="6" rx="1" />
            </svg>
            Réduire
          </button>
          {onExit ? (
            <button
              data-focusable
              onClick={exit}
              className="focusable rounded-[var(--radius)] bg-white/12 px-[1.3rem] py-[0.7rem] text-[1.1rem] font-semibold text-white"
            >
              ✕ Quitter
            </button>
          ) : (
            <Link
              href={`/title/${item.id}`}
              data-focusable
              className="focusable rounded-[var(--radius)] bg-white/12 px-[1.3rem] py-[0.7rem] text-[1.1rem] font-semibold text-white"
            >
              ✕ Quitter
            </Link>
          )}
        </div>
      </div>
    </div>
  );
}
