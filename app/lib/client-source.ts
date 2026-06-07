"use client";

/*
 * Client-side IPTV source store.
 *
 * NOVA+ ships as a static export bundled inside the Android-TV APK, so there is
 * no Node server: the WebView fetches and parses the playlist (M3U/Xtream) and
 * EPG (XMLTV) directly. The pure parsers (m3u.ts / xmltv.ts) are reused as-is.
 *
 * Cross-origin note: inside the APK the WebView enables universal access from
 * the file origin, so these fetches reach the provider without CORS. In a plain
 * browser (dev) third-party hosts may block CORS — use a same-origin/proxied URL
 * or the bundled demo for dev.
 *
 * State is exposed via useSyncExternalStore so components stay pure and all
 * readers update together when the source loads or the config changes.
 */

import { useSyncExternalStore } from "react";
import { parseM3U } from "./m3u";
import { parseXmltv } from "./xmltv";
import { nowNext as computeNowNext } from "./epg";
import { smartSearch } from "./search";
import type { EpgIndex, Playlist } from "./iptv-types";
import type { NowNextLite, NowNextMap } from "./view-types";

const K_PLAYLIST = "nova:playlistUrl";
const K_EPG = "nova:epgUrl";

export interface SourceConfig {
  playlistUrl: string;
  epgUrl: string;
}

export type Status = "idle" | "loading" | "ready" | "error";

export interface SourceState {
  status: Status;
  playlist: Playlist;
  epg: EpgIndex;
  error?: string;
  config: SourceConfig;
}

const EMPTY_PLAYLIST: Playlist = { channels: [], groups: [], total: 0 };

let state: SourceState = {
  status: "idle",
  playlist: EMPTY_PLAYLIST,
  epg: new Map(),
  config: { playlistUrl: "", epgUrl: "" },
};
let inflight: Promise<void> | null = null;
let loadedKey = "";

const listeners = new Set<() => void>();
function emit() {
  state = { ...state }; // new ref so useSyncExternalStore sees a change
  for (const l of listeners) l();
}

// Build-time defaults, inlined by Next from NEXT_PUBLIC_* env (used to bake a
// default source into the APK; the user can still override on /settings).
const DEFAULT_PLAYLIST = process.env.NEXT_PUBLIC_NOVA_PLAYLIST_URL || "";
const DEFAULT_EPG = process.env.NEXT_PUBLIC_NOVA_EPG_URL || "";

/** Read the configured source (localStorage override → build-time default). */
export function getConfig(): SourceConfig {
  if (typeof window === "undefined") return { playlistUrl: DEFAULT_PLAYLIST, epgUrl: DEFAULT_EPG };
  return {
    playlistUrl: window.localStorage.getItem(K_PLAYLIST) || DEFAULT_PLAYLIST,
    epgUrl: window.localStorage.getItem(K_EPG) || DEFAULT_EPG,
  };
}

export function setConfig(cfg: SourceConfig) {
  window.localStorage.setItem(K_PLAYLIST, cfg.playlistUrl);
  window.localStorage.setItem(K_EPG, cfg.epgUrl);
  // Force a reload of the source on next ensureLoaded().
  loadedKey = "";
  state = { ...state, status: "idle", config: cfg };
  emit();
}

export function clearConfig() {
  window.localStorage.removeItem(K_PLAYLIST);
  window.localStorage.removeItem(K_EPG);
  loadedKey = "";
  state = { ...state, status: "idle" };
  emit();
}

async function fetchText(url: string, timeoutMs = 25000): Promise<string> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.text();
  } finally {
    clearTimeout(t);
  }
}

async function doLoad(config: SourceConfig): Promise<void> {
  let playlist: Playlist = EMPTY_PLAYLIST;
  let epg: EpgIndex = new Map();
  let error: string | undefined;

  if (!config.playlistUrl) {
    state = { status: "ready", playlist, epg, config };
    emit();
    return;
  }

  try {
    playlist = parseM3U(await fetchText(config.playlistUrl));
  } catch (e) {
    state = { status: "error", playlist: EMPTY_PLAYLIST, epg, config, error: `Playlist: ${(e as Error).message}` };
    emit();
    return;
  }

  if (config.epgUrl) {
    try {
      const wanted = new Set(playlist.channels.map((c) => c.epgId).filter(Boolean));
      epg = parseXmltv(await fetchText(config.epgUrl), wanted);
    } catch (e) {
      error = `EPG: ${(e as Error).message}`;
    }
  }

  state = { status: "ready", playlist, epg, config, error };
  emit();
}

/** Load the source if not already loaded for the current config. */
export function ensureLoaded(): Promise<void> {
  if (typeof window === "undefined") return Promise.resolve();
  const config = getConfig();
  const key = `${config.playlistUrl}\n${config.epgUrl}`;
  if (key === loadedKey && state.status !== "idle") return inflight ?? Promise.resolve();
  if (inflight && key === loadedKey) return inflight;

  loadedKey = key;
  state = { ...state, status: "loading", config };
  emit();
  inflight = doLoad(config).finally(() => {
    inflight = null;
  });
  return inflight;
}

export function reload(): Promise<void> {
  loadedKey = "";
  return ensureLoaded();
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}
function getSnapshot(): SourceState {
  return state;
}
function getServerSnapshot(): SourceState {
  return state;
}

/** Reactive source state; triggers a load on first use. */
export function useSource(): SourceState {
  const s = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  if (typeof window !== "undefined" && s.status === "idle") {
    // Kick off the load (no setState during render — ensureLoaded schedules it).
    void ensureLoaded();
  }
  return s;
}

/* -------------------------- derived lookups (sync) ------------------------- */

export function channelById(id: string) {
  return state.playlist.channels.find((c) => c.id === id) ?? null;
}

export function channelsByIds(ids: string[]) {
  const byId = new Map(state.playlist.channels.map((c) => [c.id, c]));
  return ids.map((id) => byId.get(id)).filter(Boolean);
}

export function searchChannels(q: string, limit = 80) {
  if (q.trim().length < 2) return [];
  // Recherche intelligente : synonymes multilingues + score de pertinence.
  return smartSearch(state.playlist.channels, q, limit);
}

export function nowNextFor(id: string): NowNextLite | null {
  const ch = channelById(id);
  if (!ch || !ch.epgId) return null;
  const { current, next } = computeNowNext(state.epg, ch.epgId);
  return current
    ? { title: current.title, start: current.start, stop: current.stop, nextTitle: next?.title }
    : null;
}

export function nowNextMap(): NowNextMap {
  const map: NowNextMap = {};
  if (state.epg.size === 0) return map;
  for (const ch of state.playlist.channels) {
    const nn = nowNextFor(ch.id);
    if (nn) map[ch.id] = nn;
  }
  return map;
}
