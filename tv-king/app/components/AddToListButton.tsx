"use client";

// =========================================================
//  AddToListButton.tsx — Bouton « Ma liste » (toggle réversible)
// =========================================================
//  Ajoute / retire le titre de « Ma liste ». Réversible d'un appui,
//  jamais destructif. Confirme vocalement l'action (narration).
// =========================================================

import { narration } from "../lib/narration";
import { useMyList } from "../lib/mylist";

export function AddToListButton({ id, title }: { id: string; title: string }) {
  const { has, toggle } = useMyList();
  const inList = has(id);

  function onClick() {
    toggle(id);
    narration.confirm(
      inList ? `${title} retiré de ma liste` : `${title} ajouté à ma liste`,
    );
  }

  return (
    <button
      type="button"
      className="focusable"
      data-focusable
      data-nav-id="detail-list"
      aria-label={inList ? "Retirer de ma liste" : "Ajouter à ma liste"}
      aria-pressed={inList}
      onClick={onClick}
      style={{
        cursor: "pointer",
        padding: "0.9rem 1.6rem",
        borderRadius: "999px",
        background: inList ? "rgba(227,185,107,0.18)" : "rgba(255,255,255,0.12)",
        color: "var(--text-high)",
        fontWeight: 700,
        fontSize: "1.2rem",
        border: inList
          ? "1px solid var(--gold)"
          : "1px solid rgba(255,255,255,0.2)",
      }}
    >
      {inList ? "★ Dans ma liste" : "☆ Ajouter à ma liste"}
    </button>
  );
}
