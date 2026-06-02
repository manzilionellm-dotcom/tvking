"use client";

// =========================================================
//  mylist.ts — « Ma liste » (favoris persistés, sans serveur)
// =========================================================
//  Petit magasin localStorage + hook React. Aucune action destructive
//  dangereuse : ajouter/retirer est réversible d'un appui. On notifie les
//  autres composants montés via un évènement custom pour qu'ils se
//  rafraîchissent (la page Liste et le bouton de la fiche restent en
//  phase sans état global lourd).
// =========================================================

import { useCallback, useEffect, useState } from "react";

const KEY = "tvking.mylist.v1";
const EVENT = "tvking-mylist-changed";

function read(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as string[]) : [];
  } catch {
    return [];
  }
}

function write(ids: string[]): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(ids));
    window.dispatchEvent(new CustomEvent(EVENT));
  } catch {
    /* quota / mode privé → ignore */
  }
}

/// Hook : renvoie la liste courante + un toggle + un test d'appartenance.
export function useMyList() {
  const [ids, setIds] = useState<string[]>([]);

  useEffect(() => {
    const sync = () => setIds(read());
    sync();
    window.addEventListener(EVENT, sync);
    window.addEventListener("storage", sync); // autre onglet
    return () => {
      window.removeEventListener(EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const toggle = useCallback((id: string) => {
    const cur = read();
    const next = cur.includes(id)
      ? cur.filter((x) => x !== id)
      : [...cur, id];
    write(next);
  }, []);

  const has = useCallback((id: string) => ids.includes(id), [ids]);

  return { ids, toggle, has };
}
