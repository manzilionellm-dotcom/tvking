"use client";

import { useEffect, useState } from "react";
import type { MediaItem } from "../lib/data";
import { LevelBadge, LiveBadge } from "./Badge";

/*
 * Hero / billboard carousel. Auto-advances slowly (no audio, respects
 * reduced-motion) but the user keeps control via focusable indicators — NN/g:
 * video/feature content is only useful when the user can control it.
 * The hero answers the "what do I watch right now?" question within the
 * documented 60–90s attention window.
 */
export default function Hero({ slides }: { slides: MediaItem[] }) {
  const [i, setI] = useState(0);
  const slide = slides[i];

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || slides.length < 2) return;
    const t = setInterval(() => setI((p) => (p + 1) % slides.length), 9000);
    return () => clearInterval(t);
  }, [slides.length]);

  return (
    <header className="relative mb-[1.5rem] h-[58vh] min-h-[24rem] w-full overflow-hidden">
      {/* Backdrop */}
      <div
        key={slide.id}
        className="absolute inset-0 transition-opacity duration-700"
        style={{ background: `linear-gradient(120deg, ${slide.art.from}, ${slide.art.to})` }}
      />
      {/* Legibility scrims: bottom + left, so text on artwork stays readable. */}
      <div className="absolute inset-0 bg-gradient-to-t from-[var(--bg)] via-[var(--bg)]/40 to-transparent" />
      <div className="absolute inset-0 bg-gradient-to-r from-[var(--bg)]/90 via-transparent to-transparent" />

      <div className="relative flex h-full flex-col justify-end gap-[1rem] px-[var(--safe-x)] pb-[2.5rem]">
        <div className="flex items-center gap-[0.7rem]">
          {slide.live && <LiveBadge state={slide.live} />}
          {slide.level && <LevelBadge level={slide.level} />}
          {slide.league && (
            <span className="text-[1rem] font-semibold text-[var(--text-medium)]">{slide.league}</span>
          )}
        </div>

        <h1 className="max-w-[36ch] text-[3.4rem] font-extrabold leading-[1.05] tracking-tight text-[var(--text-high)]">
          {slide.title}
        </h1>
        <p className="max-w-[48ch] text-[1.4rem] text-[var(--text-medium)]">{slide.subtitle}</p>

        <div className="mt-[0.6rem] flex items-center gap-[1rem]">
          <button
            data-focusable
            className="focusable flex items-center gap-[0.6rem] rounded-[var(--radius)] bg-[var(--gold)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black"
          >
            <svg className="h-[1.3rem] w-[1.3rem]" viewBox="0 0 24 24" fill="currentColor">
              <path d="M8 5v14l11-7z" />
            </svg>
            {slide.live === "live" ? "Regarder en direct" : "Lecture"}
          </button>
          <button
            data-focusable
            className="focusable rounded-[var(--radius)] bg-white/15 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-high)]"
          >
            Plus d&apos;infos
          </button>

          {/* Slide indicators — focusable for D-pad control. */}
          {slides.length > 1 && (
            <div className="ml-[1rem] flex items-center gap-[0.5rem]">
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
