/*
 * NOVA+ source configuration.
 *
 * The user points NOVA+ at their provider with a playlist URL (M3U or Xtream
 * `get.php`) and an optional XMLTV EPG URL — exactly the two inputs TiViMate
 * asks for on first run. We resolve, in order:
 *   1. a cookie the user set on /settings (per-device, no rebuild needed),
 *   2. environment variables (deployment default / panel injection),
 *   3. a public fallback so a fresh install still shows channels.
 *
 * Xtream credentials are accepted as a convenience and converted to the
 * equivalent M3U `get.php` URL, since M3U is the lowest common denominator.
 */

import { cookies } from "next/headers";

export interface SourceConfig {
  playlistUrl: string;
  epgUrl: string;
}

export const COOKIE_PLAYLIST = "nova_playlist_url";
export const COOKIE_EPG = "nova_epg_url";

/** Public fallback (iptv-org's free, publicly-listed streams) so it runs OOTB. */
const DEFAULT_PLAYLIST =
  process.env.NOVA_PLAYLIST_URL || "https://iptv-org.github.io/iptv/index.m3u";
const DEFAULT_EPG = process.env.NOVA_EPG_URL || "";

/** Read the active source config for this request (cookie overrides env). */
export async function getConfig(): Promise<SourceConfig> {
  const store = await cookies();
  return {
    playlistUrl: store.get(COOKIE_PLAYLIST)?.value || DEFAULT_PLAYLIST,
    epgUrl: store.get(COOKIE_EPG)?.value || DEFAULT_EPG,
  };
}

/** Build the M3U URL for Xtream credentials (server / user / pass). */
export function xtreamToM3U(server: string, username: string, password: string): string {
  const base = server.replace(/\/+$/, "");
  const u = encodeURIComponent(username);
  const p = encodeURIComponent(password);
  return `${base}/get.php?username=${u}&password=${p}&type=m3u_plus&output=ts`;
}

/** Build the XMLTV EPG URL for Xtream credentials. */
export function xtreamToEpg(server: string, username: string, password: string): string {
  const base = server.replace(/\/+$/, "");
  const u = encodeURIComponent(username);
  const p = encodeURIComponent(password);
  return `${base}/xmltv.php?username=${u}&password=${p}`;
}
