/*
 * Persisted film-download store, versioned like the resume store.
 *
 * The zero-attente rule: a film is downloaded to the device before playback,
 * so playing it is instantaneous — no buffering, no spinner, ever. Download
 * progress itself is determinate (0→100 %, a bar, never a wheel), and a film
 * only enters this store once it is fully ready.
 *
 * Pure logic; only load/save touch localStorage, defensively.
 */

export const DOWNLOADS_KEY = "tvking.v1.downloads";

/** LRU cap — a device is not an unbounded disk. */
export const MAX_DOWNLOADS = 200;

export interface DownloadEntry {
  /** Completion timestamp (ms epoch) — drives LRU eviction. */
  at: number;
}

export interface DownloadStore {
  v: 1;
  entries: Record<string, DownloadEntry>;
}

export function emptyDownloads(): DownloadStore {
  return { v: 1, entries: {} };
}

function isEntry(e: unknown): e is DownloadEntry {
  if (typeof e !== "object" || e === null) return false;
  const c = e as Record<string, unknown>;
  return typeof c.at === "number" && Number.isFinite(c.at);
}

/** Defensive parse: anything unexpected → clean store, junk entries dropped. */
export function parseDownloads(raw: string | null): DownloadStore {
  if (!raw) return emptyDownloads();
  try {
    const data: unknown = JSON.parse(raw);
    if (typeof data !== "object" || data === null) return emptyDownloads();
    const store = data as Record<string, unknown>;
    if (store.v !== 1 || typeof store.entries !== "object" || store.entries === null) {
      return emptyDownloads();
    }
    const entries: Record<string, DownloadEntry> = {};
    for (const [id, entry] of Object.entries(store.entries)) {
      if (isEntry(entry)) entries[id] = entry;
    }
    return { v: 1, entries };
  } catch {
    return emptyDownloads();
  }
}

/** Mark a film as fully downloaded (pure); oldest entries evicted past the cap. */
export function withDownloaded(store: DownloadStore, id: string, now: number): DownloadStore {
  const entries = { ...store.entries, [id]: { at: now } };
  const ids = Object.keys(entries);
  if (ids.length > MAX_DOWNLOADS) {
    ids
      .sort((a, b) => entries[a].at - entries[b].at)
      .slice(0, ids.length - MAX_DOWNLOADS)
      .forEach((old) => delete entries[old]);
  }
  return { v: 1, entries };
}

export function isDownloaded(store: DownloadStore, id: string): boolean {
  return id in store.entries;
}

/* ------------------------- browser-side thin wrappers ---------------------- */

export function loadDownloads(): DownloadStore {
  if (typeof window === "undefined") return emptyDownloads();
  try {
    return parseDownloads(window.localStorage.getItem(DOWNLOADS_KEY));
  } catch {
    return emptyDownloads();
  }
}

export function saveDownloads(store: DownloadStore): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(DOWNLOADS_KEY, JSON.stringify(store));
  } catch {
    // Storage full — the film simply re-downloads next time.
  }
}
