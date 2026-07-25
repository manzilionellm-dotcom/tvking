/*
 * Persisted resume-playback store ("Reprendre"), versioned so future schema
 * changes can migrate instead of corrupting (storage is long-lived on a box).
 *
 * The store logic is pure (testable in node); only load/save touch
 * localStorage, defensively — a corrupt or foreign value never throws, it
 * just yields a fresh store.
 */

export const RESUME_KEY = "tvking.v1.resume";

/** Watched ≥ this fraction → treated as finished and dropped from the store. */
export const FINISHED_AT = 0.97;

/** LRU cap so the store cannot grow unboundedly on a shared box. */
export const MAX_ENTRIES = 100;

export interface ResumeEntry {
  /** Position in seconds. */
  pos: number;
  /** Duration in seconds (for progress bars). */
  dur: number;
  /** Last-update timestamp (ms epoch) — drives LRU eviction. */
  at: number;
}

export interface ResumeStore {
  v: 1;
  entries: Record<string, ResumeEntry>;
}

export function emptyStore(): ResumeStore {
  return { v: 1, entries: {} };
}

function isEntry(e: unknown): e is ResumeEntry {
  if (typeof e !== "object" || e === null) return false;
  const c = e as Record<string, unknown>;
  return (
    typeof c.pos === "number" &&
    Number.isFinite(c.pos) &&
    typeof c.dur === "number" &&
    Number.isFinite(c.dur) &&
    typeof c.at === "number"
  );
}

/** Defensive parse: anything unexpected (bad JSON, wrong version, junk entries) → clean store. */
export function parseStore(raw: string | null): ResumeStore {
  if (!raw) return emptyStore();
  try {
    const data: unknown = JSON.parse(raw);
    if (typeof data !== "object" || data === null) return emptyStore();
    const store = data as Record<string, unknown>;
    if (store.v !== 1 || typeof store.entries !== "object" || store.entries === null) {
      return emptyStore();
    }
    const entries: Record<string, ResumeEntry> = {};
    for (const [id, entry] of Object.entries(store.entries)) {
      if (isEntry(entry)) entries[id] = entry;
    }
    return { v: 1, entries };
  } catch {
    return emptyStore();
  }
}

/**
 * Record a position (pure). Finished items are removed — "Reprendre" must
 * never offer the last 3 % of a programme. Oldest entries are evicted past
 * MAX_ENTRIES.
 */
export function withPosition(
  store: ResumeStore,
  id: string,
  pos: number,
  dur: number,
  now: number
): ResumeStore {
  const entries = { ...store.entries };
  if (dur > 0 && pos / dur >= FINISHED_AT) {
    delete entries[id];
    return { v: 1, entries };
  }
  entries[id] = { pos: Math.max(0, pos), dur, at: now };
  const ids = Object.keys(entries);
  if (ids.length > MAX_ENTRIES) {
    ids
      .sort((a, b) => entries[a].at - entries[b].at)
      .slice(0, ids.length - MAX_ENTRIES)
      .forEach((old) => delete entries[old]);
  }
  return { v: 1, entries };
}

/** Saved position in seconds, or null when none. */
export function positionOf(store: ResumeStore, id: string): number | null {
  const e = store.entries[id];
  return e ? e.pos : null;
}

/* ------------------------- browser-side thin wrappers ---------------------- */

/*
 * Parsed-store cache keyed on the raw string. useSyncExternalStore compares
 * snapshots by identity, so a fresh object on every read would loop forever;
 * re-parsing only when the stored string actually changed keeps the snapshot
 * stable (and saves a JSON.parse per render).
 */
let cache: { raw: string | null; store: ResumeStore } | null = null;

export function loadResume(): ResumeStore {
  if (typeof window === "undefined") return emptyStore();
  let raw: string | null = null;
  try {
    raw = window.localStorage.getItem(RESUME_KEY);
  } catch {
    return emptyStore();
  }
  if (cache && cache.raw === raw) return cache.store;
  const store = parseStore(raw);
  cache = { raw, store };
  return store;
}

export function saveResume(store: ResumeStore): void {
  if (typeof window === "undefined") return;
  const raw = JSON.stringify(store);
  try {
    window.localStorage.setItem(RESUME_KEY, raw);
  } catch {
    // Storage full or unavailable — resume is a nicety, never a crash.
  }
  cache = { raw, store };
}
