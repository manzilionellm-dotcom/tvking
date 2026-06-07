"use client";

// =========================================================
//  list/page.tsx — « Ma liste »
// =========================================================
//  Affiche les titres ajoutés (persistés en localStorage). État vide
//  pédagogique qui explique comment ajouter. Aucune suppression
//  dangereuse : on retire un titre depuis sa fiche, d'un appui réversible.
// =========================================================

import { MediaCard } from "../components/MediaCard";
import { getById } from "../lib/data";
import { useMyList } from "../lib/mylist";

export default function ListPage() {
  const { ids } = useMyList();
  const items = ids
    .map((id) => getById(id))
    .filter((m): m is NonNullable<typeof m> => m !== undefined);

  return (
    <div>
      <h1 className="font-serif" style={{ fontSize: "3rem", margin: "0 0 1.2rem" }}>
        ⭐ Ma liste
      </h1>

      {items.length === 0 ? (
        <div
          style={{
            padding: "2.5rem",
            borderRadius: "var(--radius-lg)",
            background: "var(--surface-1)",
            border: "1px dashed rgba(255,255,255,0.16)",
            fontSize: "1.3rem",
            color: "var(--text-medium)",
            maxWidth: "44rem",
          }}
        >
          Votre liste est vide. Ouvrez la fiche d'un programme et choisissez
          « ☆ Ajouter à ma liste » pour le retrouver ici.
        </div>
      ) : (
        <div style={{ display: "flex", flexWrap: "wrap", gap: "1.4rem" }}>
          {items.map((item) => (
            <MediaCard key={item.id} item={item} />
          ))}
        </div>
      )}
    </div>
  );
}
