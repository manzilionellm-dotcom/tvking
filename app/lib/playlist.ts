/*
 * Persisted IPTV playlist store ("Ma TV"), versioned like the resume store so
 * future schema changes migrate instead of corrupting. Pure parse/serialize;
 * only load/save touch localStorage, defensively.
 */

import type { Channel } from "./m3u";

export const PLAYLIST_KEY = "tvking.v1.playlist";

/** Hard cap: an absurdly large playlist must not blow up localStorage. */
export const MAX_CHANNELS = 2000;

export interface PlaylistStore {
  v: 1;
  channels: Channel[];
}

export function emptyPlaylist(): PlaylistStore {
  return { v: 1, channels: [] };
}

function isChannel(c: unknown): c is Channel {
  if (typeof c !== "object" || c === null) return false;
  const ch = c as Record<string, unknown>;
  return (
    typeof ch.id === "string" &&
    typeof ch.name === "string" &&
    typeof ch.url === "string" &&
    (ch.logo === undefined || typeof ch.logo === "string") &&
    (ch.group === undefined || typeof ch.group === "string")
  );
}

/** Defensive parse: anything unexpected → empty playlist, junk entries dropped. */
export function parsePlaylist(raw: string | null): PlaylistStore {
  if (!raw) return emptyPlaylist();
  try {
    const data: unknown = JSON.parse(raw);
    if (typeof data !== "object" || data === null) return emptyPlaylist();
    const store = data as Record<string, unknown>;
    if (store.v !== 1 || !Array.isArray(store.channels)) return emptyPlaylist();
    return { v: 1, channels: store.channels.filter(isChannel).slice(0, MAX_CHANNELS) };
  } catch {
    return emptyPlaylist();
  }
}

/** Replace the whole playlist (pure) — an import always replaces, capped. */
export function withChannels(channels: Channel[]): PlaylistStore {
  return { v: 1, channels: channels.slice(0, MAX_CHANNELS) };
}

/* ------------------------- browser-side thin wrappers ---------------------- */

export function loadPlaylist(): PlaylistStore {
  if (typeof window === "undefined") return emptyPlaylist();
  try {
    return parsePlaylist(window.localStorage.getItem(PLAYLIST_KEY));
  } catch {
    return emptyPlaylist();
  }
}

export function savePlaylist(store: PlaylistStore): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PLAYLIST_KEY, JSON.stringify(store));
  } catch {
    // Storage full — the playlist stays in memory for this session.
  }
}
