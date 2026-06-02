"use client";

// =========================================================
//  Hero.tsx — Billboard d'accueil (carrousel maîtrisé)
// =========================================================
//  Grand visuel ~58vh avec titre serif, 2 actions (Lecture / Plus
//  d'infos) et des indicateurs de slide focusables. Auto-avance ~9s,
//  MAIS désactivée si réduction des animations ou s'il n'y a qu'un slide
//  (autoplay maîtrisé : jamais imposé).
// =========================================================

import Link from "next/link";
import { useEffect, useState } from "react";
import type { MediaItem } from "../lib/data";
import { getUniverseMeta } from "../lib/data";
import { usePreferences } from "../lib/preferences";

const ADVANCE_MS = 9000;

export function Hero({ items }: { items: MediaItem[] }) {
  const { prefs } = usePreferences();
  const [index, setIndex] = useState(0);

  const count = items.length;
  const autoplay = !prefs.reducedMotion && count > 1;

  useEffect(() => {
    if (!autoplay) return;
    const t = setInterval(() => {
      setIndex((i) => (i + 1) % count);
    }, ADVANCE_MS);
    return () => clearInterval(t);
  }, [autoplay, count]);

  if (count === 0) return null;
  const item = items[Math.min(index, count - 1)];
  const meta = getUniverseMeta(item.universe);

  return (
    <section
      aria-label="À la une"
      style={{
        position: "relative",
        height: "58vh",
        minHeight: "26rem",
        borderRadius: "var(--radius-lg)",
        overflow: "hidden",
        marginBottom: "2.4rem",
        background: `linear-gradient(125deg, ${item.art.from}, ${item.art.to})`,
        transition: "background var(--t-slow) ease",
        display: "flex",
        alignItems: "flex-end",
      }}
    >
      {/* Scrims de lisibilité (bas + gauche). */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(to top, rgba(0,0,0,0.72), transparent 55%), linear-gradient(to right, rgba(0,0,0,0.6), transparent 60%)",
        }}
      />

      <div
        style={{
          position: "relative",
          padding: "2.5rem",
          maxWidth: "46rem",
        }}
      >
        <span
          style={{
            display: "inline-block",
            fontSize: "1rem",
            fontWeight: 800,
            letterSpacing: "0.08em",
            color: meta.accentVar,
            marginBottom: "0.6rem",
          }}
        >
          {meta.icon} {meta.label.toUpperCase()}
        </span>
        <h1
          className="font-serif"
          style={{
            fontSize: "4rem",
            lineHeight: 1.05,
            margin: "0 0 0.6rem",
            color: "var(--text-high)",
          }}
        >
          {item.title}
        </h1>
        <p
          style={{
            fontSize: "1.4rem",
            color: "var(--text-medium)",
            margin: "0 0 1.6rem",
          }}
        >
          {item.subtitle}
        </p>

        <div style={{ display: "flex", gap: "1rem", alignItems: "center" }}>
          <Link
            href={`/watch/${item.id}`}
            className="focusable"
            data-focusable
            data-nav-id="hero-play"
            aria-label={`Lecture de ${item.title}`}
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "0.6rem",
              padding: "0.9rem 1.8rem",
              borderRadius: "999px",
              background: "var(--gold-grad)",
              color: "#1a1300",
              fontWeight: 800,
              fontSize: "1.25rem",
              textDecoration: "none",
            }}
          >
            ▶ Lecture
          </Link>
          <Link
            href={`/title/${item.id}`}
            className="focusable"
            data-focusable
            data-nav-id="hero-info"
            aria-label={`Plus d'infos sur ${item.title}`}
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "0.6rem",
              padding: "0.9rem 1.6rem",
              borderRadius: "999px",
              background: "rgba(255,255,255,0.14)",
              color: "var(--text-high)",
              fontWeight: 700,
              fontSize: "1.2rem",
              textDecoration: "none",
              border: "1px solid rgba(255,255,255,0.22)",
            }}
          >
            ＋ Plus d'infos
          </Link>
        </div>
      </div>

      {/* Indicateurs de slide (focusables, pilule active dorée). */}
      {count > 1 && (
        <div
          style={{
            position: "absolute",
            bottom: "1.4rem",
            right: "2rem",
            display: "flex",
            gap: "0.6rem",
          }}
        >
          {items.map((s, i) => (
            <button
              key={s.id}
              type="button"
              className="focusable"
              data-focusable
              data-nav-id={`hero-dot-${i}`}
              aria-label={`Aller au slide ${i + 1} : ${s.title}`}
              onClick={() => setIndex(i)}
              style={{
                cursor: "pointer",
                height: "0.6rem",
                width: i === index ? "2.2rem" : "0.6rem",
                borderRadius: "999px",
                border: "none",
                background:
                  i === index ? "var(--gold-grad)" : "rgba(255,255,255,0.4)",
                transition: "width var(--t-fast) ease",
              }}
            />
          ))}
        </div>
      )}
    </section>
  );
}
