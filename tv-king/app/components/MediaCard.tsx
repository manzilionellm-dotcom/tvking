"use client";

// =========================================================
//  MediaCard.tsx — Vignette de contenu (3 formes)
// =========================================================
//  Formes : "wide" 16:9 (vidéos), "square" 1:1 (logos/chaînes),
//  "poster" 2:3 (films/séries). Chaque carte est un LIEN focusable qui
//  mène à la fiche détail. Affiche : badge d'état, overlay (horloge +
//  score), label centré (carrés), barre « Reprendre », et un bloc méta.
//
//  Accessibilité : aria-label riche et explicite, lu par la narration.
//  Le liseré or au focus vient de la classe .focusable (design system).
// =========================================================

import Link from "next/link";
import type { CSSProperties } from "react";
import { getUniverseMeta, type MediaItem } from "../lib/data";
import { LevelBadge, LiveBadge } from "./Badge";

/// Dimensions par forme (en rem → suivent la mise à l'échelle globale).
const SIZE: Record<MediaItem["shape"], { w: string; h: string }> = {
  wide: { w: "22rem", h: "12.4rem" },
  poster: { w: "13rem", h: "19.5rem" },
  square: { w: "13rem", h: "13rem" },
};

/// Construit une description parlée claire pour les lecteurs d'écran et
/// la narration vocale (« Derby des Lumières, Sports, en direct, 2 – 1 »).
function describe(item: MediaItem): string {
  const parts: string[] = [item.title];
  parts.push(getUniverseMeta(item.universe).label);
  if (item.live) parts.push("en direct");
  else if (item.badge === "upcoming" && item.startsIn)
    parts.push(item.startsIn);
  else if (item.badge === "replay") parts.push("rediffusion");
  else if (item.badge === "new") parts.push("nouveau");
  if (item.score) parts.push(`score ${item.score}`);
  if (item.channel) parts.push(item.channel);
  if (item.duration) parts.push(item.duration);
  if (item.progress && item.progress > 0)
    parts.push(`reprendre à ${Math.round(item.progress * 100)} %`);
  return parts.join(", ");
}

export function MediaCard({ item }: { item: MediaItem }) {
  const size = SIZE[item.shape];
  const isSquare = item.shape === "square";

  const artStyle: CSSProperties = {
    position: "relative",
    width: size.w,
    height: size.h,
    borderRadius: "var(--radius)",
    overflow: "hidden",
    background: `linear-gradient(150deg, ${item.art.from}, ${item.art.to})`,
    // Légère bordure interne pour détacher la carte du fond.
    boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.06)",
    display: "flex",
    flexDirection: "column",
    justifyContent: "flex-end",
  };

  return (
    <Link
      href={`/title/${item.id}`}
      className="focusable"
      data-focusable
      data-nav-id={item.id}
      data-amb-from={item.art.from}
      data-amb-to={item.art.to}
      aria-label={describe(item)}
      style={{
        display: "inline-block",
        textDecoration: "none",
        color: "var(--text-high)",
        borderRadius: "var(--radius)",
      }}
    >
      <div style={artStyle}>
        {/* Scrim bas pour lisibilité des overlays. */}
        <div
          aria-hidden
          style={{
            position: "absolute",
            inset: 0,
            background:
              "linear-gradient(to top, rgba(0,0,0,0.55), transparent 45%)",
          }}
        />

        {/* Badge d'état en haut à gauche. */}
        {item.badge && item.badge !== "none" && (
          <div style={{ position: "absolute", top: "0.6rem", left: "0.6rem" }}>
            <LiveBadge kind={item.badge} />
          </div>
        )}

        {/* Horloge + score (overlay bas, pour le sport). */}
        {(item.clock || item.score) && (
          <div
            style={{
              position: "relative",
              padding: "0.5rem 0.7rem",
              display: "flex",
              justifyContent: "space-between",
              alignItems: "flex-end",
              fontSize: "0.95rem",
              fontWeight: 700,
            }}
          >
            {item.score && <span>{item.score}</span>}
            {item.clock && (
              <span style={{ color: "var(--text-high)" }}>{item.clock}</span>
            )}
          </div>
        )}

        {/* Label centré pour les carrés (logos de chaînes). */}
        {isSquare && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              textAlign: "center",
              padding: "0.8rem",
              gap: "0.3rem",
            }}
          >
            <span style={{ fontSize: "1.3rem", fontWeight: 800 }}>
              {item.title}
            </span>
            {item.channel && (
              <span
                style={{ fontSize: "0.85rem", color: "var(--text-medium)" }}
              >
                {item.channel}
              </span>
            )}
          </div>
        )}

        {/* Barre « Reprendre » (progression de lecture). */}
        {item.progress !== undefined && item.progress > 0 && (
          <div
            aria-hidden
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              bottom: 0,
              height: "0.35rem",
              background: "rgba(0,0,0,0.45)",
            }}
          >
            <div
              style={{
                width: `${Math.min(100, item.progress * 100)}%`,
                height: "100%",
                background: "var(--gold-grad)",
              }}
            />
          </div>
        )}
      </div>

      {/* Bloc méta (sauf carrés, qui portent le label dans l'affiche). */}
      {!isSquare && (
        <div style={{ width: size.w, paddingTop: "0.5rem" }}>
          <div
            style={{
              fontSize: "1.05rem",
              fontWeight: 700,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {item.title}
          </div>
          <div
            style={{
              marginTop: "0.15rem",
              fontSize: "0.85rem",
              color: "var(--text-medium)",
              display: "flex",
              alignItems: "center",
              gap: "0.5rem",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {item.level && <LevelBadge level={item.level} />}
            <span
              style={{
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {item.subtitle ??
                item.league ??
                item.instructor ??
                (item.lessons ? `${item.lessons} leçons` : "")}
            </span>
          </div>
        </div>
      )}
    </Link>
  );
}
