import "server-only";

/*
 * Server-side assembly of the serializable view-models the pages hand to their
 * Client Components. Centralises the loadSource + EPG join so pages stay thin.
 */

import { loadSource } from "./source";
import { nowNext } from "./epg";
import type { NowNextMap } from "./view-types";
import type { ChannelGroup } from "./iptv-types";

export interface BrowseView {
  groups: ChannelGroup[];
  nowNext: NowNextMap;
  total: number;
  error?: string;
  config: { playlistUrl: string; epgUrl: string };
}

/** Build the now/next map for every channel that has EPG data. */
function buildNowNextMap(
  channels: { id: string; epgId: string }[],
  epg: Awaited<ReturnType<typeof loadSource>>["epg"],
  at = Date.now()
): NowNextMap {
  const map: NowNextMap = {};
  if (epg.size === 0) return map;
  for (const ch of channels) {
    if (!ch.epgId) continue;
    const { current, next } = nowNext(epg, ch.epgId, at);
    if (current) {
      map[ch.id] = {
        title: current.title,
        start: current.start,
        stop: current.stop,
        nextTitle: next?.title,
      };
    }
  }
  return map;
}

/** One channel's row in the guide grid (programmes clipped to the window). */
export interface GuideRow {
  id: string;
  name: string;
  number: number;
  logo?: string;
  programmes: { start: number; stop: number; title: string }[];
}

export interface GuideView {
  rows: GuideRow[];
  windowStart: number;
  windowEnd: number;
  now: number;
  hasEpg: boolean;
  total: number;
}

const GUIDE_MAX_CHANNELS = 150; // grid stays navigable; rest reachable via Accueil

/** The EPG guide view-model: a time window of programmes per channel. */
export async function getGuideView(windowHours = 4): Promise<GuideView> {
  const { playlist, epg } = await loadSource();
  // Window starts at the previous half-hour for context.
  const now = Date.now();
  const half = 30 * 60_000;
  const windowStart = Math.floor(now / half) * half;
  const windowEnd = windowStart + windowHours * 3600_000;

  const channels = playlist.channels.slice(0, GUIDE_MAX_CHANNELS);
  const rows: GuideRow[] = channels.map((ch) => {
    const list = epg.get(ch.epgId) ?? [];
    const programmes = list
      .filter((p) => p.stop > windowStart && p.start < windowEnd)
      .map((p) => ({ start: p.start, stop: p.stop, title: p.title }));
    return { id: ch.id, name: ch.name, number: ch.number, logo: ch.logo, programmes };
  });

  return { rows, windowStart, windowEnd, now, hasEpg: epg.size > 0, total: playlist.total };
}

/** The home/browse view-model. */
export async function getBrowseView(): Promise<BrowseView> {
  const { playlist, epg, config, error } = await loadSource();
  return {
    groups: playlist.groups,
    nowNext: buildNowNextMap(playlist.channels, epg),
    total: playlist.total,
    error,
    config,
  };
}
