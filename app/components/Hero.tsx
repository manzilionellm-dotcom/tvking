"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import type { MediaItem } from "../lib/data";
import { LevelBadge, LiveBadge } from "./Badge";

/*
 * Hero / billboard carousel. Auto-advances slowly (no audio, respects
 * reduced-motion) but the user keeps control via focusable indicators — NN/g:
 * video/feature content is only useful when the user can control it.
 * On touch screens the billboard is swipeable (the native carousel gesture),
 * and every advance — manual or automatic — re-arms the timer so a swipe is
 * never immediately overridden.
 * The hero answers the "what do I watch right now?" question within the
 * documented 60–90s attention window.
 */
export default function Hero({ slides }: { slides: MediaItem[] }) {
  const [i, setI] = useState(0);
  const slide = slides[i];
  const touchStart = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || slides.length < 2) return;
    const t = setTimeout(() => setI((p) => (p + 1) % slides.length), 9000);
    return () => clearTimeout(t);
  }, [slides.length, i]);

  function onTouchStart(e: React.TouchEvent) {
    const t = e.touches[0];
    touchStart.current = { x: t.clientX, y: t.clientY };
  }

  function onTouchEnd(e: React.TouchEvent) {
    const start = touchStart.current;
    touchStart.current = null;
    if (!start || slides.length < 2) return;
    const t = e.changedTouches[0];
    const dx = t.clientX - start.x;
    const dy = t.clientY - start.y;
    // A deliberate horizontal swipe, not a vertical scroll.
    if (Math.abs(dx) < 48 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    setI((p) => (p + (dx < 0 ? 1 : slides.length - 1)) % slides.length);
  }

  return (
    <header
      className="relative z-[2] mb-[1.5rem] h-[58vh] min-h-[24rem] w-full overflow-hidden max-md:h-[66vh]"
      onTouchStart={onTouchStart}
      onTouchEnd={onTouchEnd}
    >
      {/* Backdrop */}
      <div
        key={slide.id}
        className="hero-slide absolute inset-0"
        style={{ background: `linear-gradient(120deg, ${slide.art.from}, ${slide.art.to})` }}
      />
      {/* Legibility scrims: bottom + left, so text on artwork stays readable. */}
      <div className="absolute inset-0 bg-gradient-to-t from-[var(--bg)] via-[var(--bg)]/40 to-transparent" />
      <div className="absolute inset-0 bg-gradient-to-r from-[var(--bg)]/90 via-transparent to-transparent" />

      <div className="relative flex h-full flex-col justify-end gap-[1rem] px-[var(--safe-x)] pb-[2.5rem] max-md:gap-[0.7rem] max-md:pb-[1.6rem]">
        <div className="flex items-center gap-[0.7rem]">
          {slide.live && <LiveBadge state={slide.live} />}
          {slide.level && <LevelBadge level={slide.level} />}
          {slide.league && (
            <span className="text-[1rem] font-semibold text-[var(--text-medium)]">{slide.league}</span>
          )}
        </div>

        <h1 className="font-display max-w-[36ch] text-[4rem] font-extrabold leading-[1.02] tracking-tight text-[var(--text-high)] [text-shadow:0_0.2rem_1.5rem_rgba(0,0,0,0.5)] max-md:text-[2.1rem] max-md:leading-[1.08]">
          {slide.title}
        </h1>
        <p className="max-w-[48ch] text-[1.4rem] text-[var(--text-medium)] max-md:text-[1.02rem]">
          {slide.subtitle}
        </p>

        <div className="mt-[0.6rem] flex items-center gap-[1rem] max-md:mt-[0.3rem] max-md:flex-wrap max-md:gap-[0.7rem]">
          <Link
            href={`/watch/${slide.id}`}
            data-focusable
            className="focusable flex items-center gap-[0.6rem] rounded-[var(--radius)] px-[1.7rem] py-[0.85rem] text-[1.25rem] font-bold text-black shadow-[0_0.6rem_1.6rem_rgba(227,185,107,0.35)] max-md:flex-1 max-md:justify-center"
            style={{ background: "var(--gold-grad)" }}
          >
            <svg className="h-[1.3rem] w-[1.3rem]" viewBox="0 0 24 24" fill="currentColor">
              <path d="M8 5v14l11-7z" />
            </svg>
            {slide.live === "live" ? "Regarder en direct" : "Lecture"}
          </Link>
          <Link
            href={`/title/${slide.id}`}
            data-focusable
            className="focusable rounded-[var(--radius)] bg-white/15 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-high)]"
          >
            Plus d&apos;infos
          </Link>

          {/* Slide indicators — focusable for D-pad control, tappable dots on touch. */}
          {slides.length > 1 && (
            <div className="ml-[1rem] flex items-center gap-[0.5rem] max-md:ml-0 max-md:mt-[0.5rem] max-md:w-full max-md:justify-center">
              {slides.map((s, idx) => (
                <button
                  key={s.id}
                  data-focusable
                  aria-label={`Diapositive ${idx + 1}`}
                  onClick={() => setI(idx)}
                  onFocus={() => setI(idx)}
                  className="focusable h-[0.4rem] rounded-full transition-all"
                  style={{
                    width: idx === i ? "2rem" : "0.8rem",
                    background: idx === i ? "var(--gold)" : "rgba(255,255,255,0.35)",
                  }}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
