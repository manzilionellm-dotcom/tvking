import "server-only";

/*
 * Server-side source loader: fetch + parse the playlist and EPG, then cache the
 * parsed result in-process so we don't re-download multi-MB dumps on every
 * navigation. Keyed by the URL pair, with a TTL. `react`'s `cache` also dedupes
 * within a single request/render pass.
 */

import { cache } from "react";
import { parseM3U } from "./m3u";
import { parseXmltv } from "./xmltv";
import { getConfig } from "./config";
import type { EpgIndex, Playlist } from "./iptv-types";

export interface Source {
  playlist: Playlist;
  epg: EpgIndex;
  /** Echo of what was loaded, for the settings/diagnostics screen. */
  config: { playlistUrl: string; epgUrl: string };
  error?: string;
}

const TTL_MS = 30 * 60_000; // 30 min — live channel lists change rarely.
const FETCH_TIMEOUT_MS = 20_000;
const MAX_BYTES = 60 * 1024 * 1024; // guard against pathological dumps (60 MB)

type Entry = { at: number; source: Source };
const store = new Map<string, Entry>();

async function fetchText(url: string): Promise<string> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { "User-Agent": "NOVA+/1.0 (Android TV)" },
      cache: "no-store",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = await res.arrayBuffer();
    if (buf.byteLength > MAX_BYTES) throw new Error("playlist too large");
    return new TextDecoder("utf-8").decode(buf);
  } finally {
    clearTimeout(t);
  }
}

async function build(playlistUrl: string, epgUrl: string): Promise<Source> {
  const config = { playlistUrl, epgUrl };
  let playlist: Playlist = { channels: [], groups: [], total: 0 };
  let epg: EpgIndex = new Map();
  let error: string | undefined;

  try {
    const m3u = await fetchText(playlistUrl);
    playlist = parseM3U(m3u);
  } catch (e) {
    error = `Playlist: ${(e as Error).message}`;
    return { playlist, epg, config, error };
  }

  if (epgUrl) {
    try {
      const wanted = new Set(playlist.channels.map((c) => c.epgId).filter(Boolean));
      const xml = await fetchText(epgUrl);
      epg = parseXmltv(xml, wanted);
    } catch (e) {
      // EPG is optional — degrade to now/next-less UI rather than failing.
      error = `EPG: ${(e as Error).message}`;
    }
  }

  return { playlist, epg, config, error };
}

/** Load (and cache) the parsed source for the active config. */
export const loadSource = cache(async (): Promise<Source> => {
  const { playlistUrl, epgUrl } = await getConfig();
  const key = `${playlistUrl}\n${epgUrl}`;
  const hit = store.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.source;

  const source = await build(playlistUrl, epgUrl);
  // Only cache a successful playlist load (so transient errors retry next time).
  if (!source.error || source.playlist.total > 0) {
    store.set(key, { at: Date.now(), source });
  }
  return source;
});

/** Force a reload on next access (used after the user changes the source). */
export function invalidateSource(): void {
  store.clear();
}

/** Look up a channel by id within the active source. */
export async function getChannel(id: string) {
  const { playlist } = await loadSource();
  return playlist.channels.find((c) => c.id === id) ?? null;
}
