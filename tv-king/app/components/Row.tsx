// =========================================================
//  Row.tsx — Rangée horizontale de vignettes
// =========================================================
//  Un titre de rangée + une bande de MediaCards défilable
//  horizontalement. Le défilement est PILOTÉ PAR LE FOCUS : quand une
//  carte reçoit le focus, SpatialNav la recentre (scrollIntoView), ce
//  qui fait défiler la rangée naturellement. On laisse un léger « peek »
//  (padding droit) pour suggérer qu'il y a d'autres cartes à droite.
// =========================================================

import type { MediaItem } from "../lib/data";
import { MediaCard } from "./MediaCard";

export function Row({
  title,
  items,
  accentVar = "var(--gold)",
}: {
  title: string;
  items: MediaItem[];
  accentVar?: string;
}) {
  if (items.length === 0) return null;
  return (
    <section style={{ marginBottom: "2.4rem" }}>
      <h2
        style={{
          margin: "0 0 0.9rem",
          fontSize: "1.5rem",
          fontWeight: 800,
          display: "flex",
          alignItems: "center",
          gap: "0.6rem",
          color: "var(--text-high)",
        }}
      >
        {/* Petit accent coloré de l'univers en tête de rangée. */}
        <span
          aria-hidden
          style={{
            width: "0.35rem",
            height: "1.3rem",
            borderRadius: "999px",
            background: accentVar,
          }}
        />
        {title}
      </h2>

      <div
        style={{
          display: "flex",
          gap: "1.2rem",
          overflowX: "auto",
          // Espace pour que le scale(1.08) au focus ne soit pas coupé.
          padding: "0.6rem 1.25rem 0.6rem 0",
          scrollPadding: "0 6rem",
        }}
      >
        {items.map((item) => (
          <MediaCard key={item.id} item={item} />
        ))}
      </div>
    </section>
  );
}
