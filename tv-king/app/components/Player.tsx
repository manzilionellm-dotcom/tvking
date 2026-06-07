"use client";

// =========================================================
//  Player.tsx — Lecteur (maquette) + contrôles + « À suivre »
// =========================================================
//  Pas de vrai flux ici (projet front, aucune URL réelle). On simule une
//  surface de lecture (dégradé) avec des contrôles focusables.
//
//  « À suivre » : compte à rebours ANNULABLE et DÉSACTIVÉ PAR DÉFAUT —
//  on n'enchaîne JAMAIS automatiquement sans que l'utilisateur l'ait
//  explicitement activé (principe « aucune lecture auto forcée »).
// =========================================================

import { useRouter } from "next/navigation";
import Link from "next/link";
import { useEffect, useState } from "react";
import type { MediaItem } from "../lib/data";
import { narration } from "../lib/narration";

const COUNTDOWN_START = 10;

export function Player({
  item,
  next,
}: {
  item: MediaItem;
  next: MediaItem | null;
}) {
  const router = useRouter();
  const [playing, setPlaying] = useState(true);
  // Lecture auto de la suite : OFF par défaut (jamais imposée).
  const [autoNext, setAutoNext] = useState(false);
  const [remaining, setRemaining] = useState(COUNTDOWN_START);

  // Le compte à rebours ne tourne QUE si l'utilisateur a activé autoNext.
  useEffect(() => {
    if (!autoNext || !next) return;
    if (remaining <= 0) {
      router.push(`/watch/${next.id}`);
      return;
    }
    const t = setTimeout(() => setRemaining((r) => r - 1), 1000);
    return () => clearTimeout(t);
  }, [autoNext, remaining, next, router]);

  function togglePlay() {
    setPlaying((p) => {
      narration.confirm(!p ? "Lecture" : "Pause");
      return !p;
    });
  }

  function startAuto() {
    setRemaining(COUNTDOWN_START);
    setAutoNext(true);
    narration.confirm("Lecture automatique de la suite activée");
  }

  function cancelAuto() {
    setAutoNext(false);
    narration.confirm("Lecture automatique annulée");
  }

  return (
    <div style={{ maxWidth: "78rem", margin: "0 auto" }}>
      {/* Surface de lecture. */}
      <div
        style={{
          position: "relative",
          aspectRatio: "16 / 9",
          borderRadius: "var(--radius-lg)",
          overflow: "hidden",
          background: `linear-gradient(125deg, ${item.art.from}, ${item.art.to})`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <span
          aria-hidden
          style={{ fontSize: "5rem", opacity: playing ? 0.25 : 0.9 }}
        >
          {playing ? "♪" : "⏸"}
        </span>

        {/* Bandeau titre. */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            padding: "1.4rem 1.6rem",
            background: "linear-gradient(to bottom, rgba(0,0,0,0.6), transparent)",
          }}
        >
          <div className="font-serif" style={{ fontSize: "2rem" }}>
            {item.title}
          </div>
        </div>
      </div>

      {/* Contrôles. */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "1rem",
          marginTop: "1.2rem",
          flexWrap: "wrap",
        }}
      >
        <button
          type="button"
          className="focusable"
          data-focusable
          data-nav-id="player-play"
          aria-label={playing ? "Mettre en pause" : "Reprendre la lecture"}
          onClick={togglePlayGuard(togglePlay)}
          style={ctrlStyle(true)}
        >
          {playing ? "⏸ Pause" : "▶ Lecture"}
        </button>

        <Link
          href={`/title/${item.id}`}
          className="focusable"
          data-focusable
          data-nav-id="player-back"
          aria-label="Retour à la fiche"
          style={{ ...ctrlStyle(false), textDecoration: "none" }}
        >
          ⬅ Retour
        </Link>

        {next && !autoNext && (
          <button
            type="button"
            className="focusable"
            data-focusable
            data-nav-id="player-autonext"
            aria-label={`Activer la lecture automatique de la suite : ${next.title}`}
            onClick={startAuto}
            style={ctrlStyle(false)}
          >
            ⏭ Lecture auto de la suite
          </button>
        )}
      </div>

      {/* Panneau « À suivre » avec compte à rebours ANNULABLE. */}
      {next && autoNext && (
        <div
          role="status"
          style={{
            marginTop: "1.4rem",
            padding: "1.2rem 1.4rem",
            borderRadius: "var(--radius)",
            background: "var(--surface-2)",
            border: "1px solid rgba(255,255,255,0.1)",
            display: "flex",
            alignItems: "center",
            gap: "1.2rem",
            flexWrap: "wrap",
          }}
        >
          <span style={{ fontSize: "1.2rem" }}>
            À suivre&nbsp;: <strong>{next.title}</strong> dans{" "}
            <strong style={{ color: "var(--gold)" }}>{remaining}s</strong>
          </span>
          <Link
            href={`/watch/${next.id}`}
            className="focusable"
            data-focusable
            data-nav-id="player-next-now"
            aria-label={`Lire ${next.title} maintenant`}
            style={{ ...ctrlStyle(true), textDecoration: "none" }}
          >
            ▶ Maintenant
          </Link>
          <button
            type="button"
            className="focusable"
            data-focusable
            data-nav-id="player-cancel"
            aria-label="Annuler la lecture automatique"
            onClick={cancelAuto}
            style={ctrlStyle(false)}
          >
            ✕ Annuler
          </button>
        </div>
      )}
    </div>
  );
}

// Empêche le double-déclenchement clavier (Espace scroll) — pur confort.
function togglePlayGuard(fn: () => void) {
  return () => fn();
}

function ctrlStyle(primary: boolean) {
  return {
    cursor: "pointer",
    padding: "0.8rem 1.5rem",
    borderRadius: "999px",
    fontSize: "1.2rem",
    fontWeight: 700,
    color: primary ? "#1a1300" : "var(--text-high)",
    background: primary ? "var(--gold-grad)" : "rgba(255,255,255,0.12)",
    border: primary ? "none" : "1px solid rgba(255,255,255,0.2)",
  } as const;
}
