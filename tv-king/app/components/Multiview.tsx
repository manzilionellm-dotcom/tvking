"use client";

// =========================================================
//  Multiview.tsx — Multi-écran sport (2 à 4 directs)
// =========================================================
//  Mosaïque de directs ; UN SEUL son actif à la fois, choisi au D-pad
//  (OK sur une tuile = activer son audio). Maquette : pas de vrai flux,
//  juste des surfaces dégradées avec score/horloge.
// =========================================================

import { useState } from "react";
import { getByUniverse } from "../lib/data";

export function Multiview() {
  const lives = getByUniverse("sports")
    .filter((m) => m.live)
    .slice(0, 4);
  const [activeId, setActiveId] = useState(lives[0]?.id ?? "");

  if (lives.length < 2) {
    return (
      <p style={{ fontSize: "1.3rem", color: "var(--text-medium)" }}>
        Pas assez de directs en ce moment pour le multi-écran.
      </p>
    );
  }

  return (
    <div>
      <h1 className="font-serif" style={{ fontSize: "3rem", margin: "0 0 0.6rem" }}>
        🔲 Multi-écran
      </h1>
      <p
        style={{
          fontSize: "1.2rem",
          color: "var(--text-medium)",
          margin: "0 0 1.4rem",
        }}
      >
        Sélectionnez une vignette (OK) pour activer son son. Une seule à la
        fois.
      </p>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(2, 1fr)",
          gap: "1rem",
          maxWidth: "70rem",
        }}
      >
        {lives.map((m) => {
          const active = m.id === activeId;
          return (
            <button
              key={m.id}
              type="button"
              className="focusable"
              data-focusable
              data-nav-id={`mv-${m.id}`}
              data-amb-from={m.art.from}
              data-amb-to={m.art.to}
              aria-label={`${m.title}. ${active ? "Son actif" : "Son coupé"}. OK pour activer le son.`}
              aria-pressed={active}
              onClick={() => setActiveId(m.id)}
              style={{
                cursor: "pointer",
                position: "relative",
                aspectRatio: "16 / 9",
                borderRadius: "var(--radius)",
                overflow: "hidden",
                border: active
                  ? "2px solid var(--gold)"
                  : "2px solid transparent",
                background: `linear-gradient(150deg, ${m.art.from}, ${m.art.to})`,
                color: "var(--text-high)",
                textAlign: "left",
                padding: 0,
              }}
            >
              <span
                aria-hidden
                style={{
                  position: "absolute",
                  inset: 0,
                  background:
                    "linear-gradient(to top, rgba(0,0,0,0.6), transparent 55%)",
                }}
              />
              {/* Indicateur audio. */}
              <span
                style={{
                  position: "absolute",
                  top: "0.6rem",
                  right: "0.7rem",
                  fontSize: "1.5rem",
                }}
              >
                {active ? "🔊" : "🔇"}
              </span>
              <span
                style={{
                  position: "absolute",
                  left: "0.8rem",
                  bottom: "0.7rem",
                  right: "0.8rem",
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "flex-end",
                  fontWeight: 800,
                }}
              >
                <span style={{ fontSize: "1.25rem" }}>{m.title}</span>
                {m.score && <span>{m.score}</span>}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
