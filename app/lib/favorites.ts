"use client";

/*
 * Favorites + recent channels, persisted per-device in localStorage.
 *
 * TiViMate keeps favorites and "last watched" client-side and instantly
 * available; we do the same. A tiny pub/sub lets every mounted component
 * (rail, cards, player) re-render when the set changes without a global store.
 */

import { useCallback, useEffect, useState } from "react";

const FAV_KEY = "nova:favorites";
const RECENT_KEY = "nova:recents";
const MAX_RECENTS = 30;

type Listener = () => void;
const listeners = new Set<Listener>();
function emit() {
  for (const l of listeners) l();
}

function read(key: string): string[] {
  if (typeof window === "undefined") return [];
  try {
    const v = JSON.parse(window.localStorage.getItem(key) || "[]");
    return Array.isArray(v) ? v.filter((x) => typeof x === "string") : [];
  } catch {
    return [];
  }
}

function write(key: string, ids: string[]) {
  window.localStorage.setItem(key, JSON.stringify(ids));
  emit();
}

/** Subscribe a component to favorites/recents changes. */
function useStore<T>(selector: () => T): T {
  const [, force] = useState(0);
  useEffect(() => {
    const l = () => force((n) => n + 1);
    listeners.add(l);
    // Sync across tabs/windows too.
    window.addEventListener("storage", l);
    return () => {
      listeners.delete(l);
      window.removeEventListener("storage", l);
    };
  }, []);
  return selector();
}

/** Hook: the set of favorite channel ids + a toggle. */
export function useFavorites() {
  const ids = useStore(() => read(FAV_KEY));
  const set = new Set(ids);

  const toggle = useCallback((id: string) => {
    const cur = read(FAV_KEY);
    const next = cur.includes(id) ? cur.filter((x) => x !== id) : [id, ...cur];
    write(FAV_KEY, next);
  }, []);

  const isFavorite = useCallback((id: string) => read(FAV_KEY).includes(id), []);

  return { favorites: ids, favoriteSet: set, toggle, isFavorite };
}

/** Record a channel as recently watched (call from the player). */
export function pushRecent(id: string) {
  if (typeof window === "undefined") return;
  const cur = read(RECENT_KEY).filter((x) => x !== id);
  write(RECENT_KEY, [id, ...cur].slice(0, MAX_RECENTS));
}

/** Hook: recently watched channel ids (most recent first). */
export function useRecents() {
  return useStore(() => read(RECENT_KEY));
}
