/*
 * Persisted user collections — "Ma liste" (saved items) and "Rappels"
 * (reminders on upcoming sport).
 *
 * These are the *investment* surfaces of the Hooked model documented in
 * docs/RESEARCH-TV-UX.md §4: what the viewer saves personalises what the app
 * shows next. Until now both buttons existed but did nothing (backlog B7 —
 * "pas de fausses fonctionnalités").
 *
 * Same contract as lib/resume.ts: the logic is pure and unit-testable, storage
 * is versioned (`tvking.v1.*`) and parsed defensively — a corrupt or foreign
 * value yields an empty collection instead of throwing on a set-top box that
 * may never be reinstalled.
 */

export const MYLIST_KEY = "tvking.v1.mylist";
export const REMINDERS_KEY = "tvking.v1.reminders";

/** Cap so a long-lived box cannot grow the store without bound. */
export const MAX_IDS = 200;

/** Ordered set of item ids, most recently added first. */
export interface IdSet {
  v: 1;
  ids: string[];
}

export function emptySet(): IdSet {
  return { v: 1, ids: [] };
}

/** Defensive parse: bad JSON / wrong version / non-string entries → empty set. */
export function parseSet(raw: string | null): IdSet {
  if (!raw) return emptySet();
  try {
    const data: unknown = JSON.parse(raw);
    if (typeof data !== "object" || data === null) return emptySet();
    const store = data as Record<string, unknown>;
    if (store.v !== 1 || !Array.isArray(store.ids)) return emptySet();
    const ids: string[] = [];
    for (const id of store.ids) {
      if (typeof id === "string" && id.length > 0 && !ids.includes(id)) ids.push(id);
    }
    return { v: 1, ids: ids.slice(0, MAX_IDS) };
  } catch {
    return emptySet();
  }
}

export function hasId(store: IdSet, id: string): boolean {
  return store.ids.includes(id);
}

/** Add to the front (most recent first), capped. Adding twice is a no-op move. */
export function addId(store: IdSet, id: string): IdSet {
  return { v: 1, ids: [id, ...store.ids.filter((x) => x !== id)].slice(0, MAX_IDS) };
}

export function removeId(store: IdSet, id: string): IdSet {
  return { v: 1, ids: store.ids.filter((x) => x !== id) };
}

export function toggleId(store: IdSet, id: string): IdSet {
  return hasId(store, id) ? removeId(store, id) : addId(store, id);
}

/* ------------------------- browser-side thin wrappers ---------------------- */

/*
 * useSyncExternalStore requires a *stable* snapshot: returning a fresh object on
 * every read would loop forever. We cache the parsed store per key and only
 * re-parse when the raw string changed.
 */
const cache = new Map<string, { raw: string | null; store: IdSet }>();
const listeners = new Set<() => void>();

function notify() {
  listeners.forEach((l) => l());
}

/** Subscribe to local writes and to changes made by another tab/screen. */
export function subscribeCollections(cb: () => void): () => void {
  listeners.add(cb);
  if (typeof window !== "undefined") window.addEventListener("storage", cb);
  return () => {
    listeners.delete(cb);
    if (typeof window !== "undefined") window.removeEventListener("storage", cb);
  };
}

export function loadSet(key: string): IdSet {
  if (typeof window === "undefined") return emptySet();
  let raw: string | null = null;
  try {
    raw = window.localStorage.getItem(key);
  } catch {
    return emptySet();
  }
  const hit = cache.get(key);
  if (hit && hit.raw === raw) return hit.store;
  const store = parseSet(raw);
  cache.set(key, { raw, store });
  return store;
}

export function saveSet(key: string, store: IdSet): void {
  if (typeof window === "undefined") return;
  const raw = JSON.stringify(store);
  try {
    window.localStorage.setItem(key, raw);
  } catch {
    // Storage full or unavailable — a saved list is a nicety, never a crash.
  }
  cache.set(key, { raw, store });
  notify();
}

/** Toggle membership and persist. Returns the new state of `id` (in / out). */
export function toggleStored(key: string, id: string): boolean {
  const next = toggleId(loadSet(key), id);
  saveSet(key, next);
  return hasId(next, id);
}
