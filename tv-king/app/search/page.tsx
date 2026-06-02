"use client";

// =========================================================
//  search/page.tsx — Recherche
// =========================================================
//  Deux entrées, pour ne perdre personne :
//   - des « chips » de suggestion FOCUSABLES (utilisables à la seule
//     télécommande, sans clavier),
//   - un champ texte libre (clavier / souris) pour qui veut taper.
//  Les résultats s'affichent en grille de MediaCards (focusables).
// =========================================================

import { useMemo, useState } from "react";
import { MediaCard } from "../components/MediaCard";
import { searchMedia, UNIVERSES } from "../lib/data";

const SUGGESTIONS = [
  "Direct",
  "Film",
  "Match",
  "Dessin animé",
  "Journal",
  "Cours",
];

export default function SearchPage() {
  const [query, setQuery] = useState("");
  const results = useMemo(() => searchMedia(query), [query]);

  return (
    <div>
      <h1 className="font-serif" style={{ fontSize: "3rem", margin: "0 0 1rem" }}>
        🔎 Rechercher
      </h1>

      {/* Champ libre (clavier/souris). */}
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Tapez un titre, une chaîne, un sport…"
        aria-label="Champ de recherche"
        style={{
          width: "100%",
          maxWidth: "40rem",
          padding: "1rem 1.2rem",
          fontSize: "1.3rem",
          borderRadius: "var(--radius)",
          border: "1px solid rgba(255,255,255,0.18)",
          background: "var(--surface-1)",
          color: "var(--text-high)",
          outline: "none",
        }}
      />

      {/* Suggestions focusables (télécommande). */}
      <div
        style={{
          display: "flex",
          gap: "0.8rem",
          flexWrap: "wrap",
          margin: "1.2rem 0 2rem",
        }}
      >
        {SUGGESTIONS.map((s) => (
          <button
            key={s}
            type="button"
            className="focusable"
            data-focusable
            data-nav-id={`sugg-${s}`}
            aria-label={`Rechercher : ${s}`}
            onClick={() => setQuery(s)}
            style={{
              cursor: "pointer",
              padding: "0.6rem 1.2rem",
              borderRadius: "999px",
              fontSize: "1.1rem",
              fontWeight: 700,
              background:
                query === s ? "rgba(227,185,107,0.18)" : "var(--surface-2)",
              color: "var(--text-high)",
              border:
                query === s
                  ? "1px solid var(--gold)"
                  : "1px solid rgba(255,255,255,0.12)",
            }}
          >
            {s}
          </button>
        ))}
      </div>

      {query && results.length === 0 && (
        <p style={{ fontSize: "1.3rem", color: "var(--text-medium)" }}>
          Aucun résultat pour « {query} ». Essayez un autre mot, ou un univers
          dans le menu&nbsp;:{" "}
          {UNIVERSES.map((u) => u.label).join(", ")}.
        </p>
      )}

      {results.length > 0 && (
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            gap: "1.4rem",
          }}
        >
          {results.map((item) => (
            <MediaCard key={item.id} item={item} />
          ))}
        </div>
      )}
    </div>
  );
}
