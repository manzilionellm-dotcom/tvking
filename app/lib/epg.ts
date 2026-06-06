/*
 * EPG helpers — derive the "now / next" pair and progress for the info bar,
 * the single most-used piece of TiViMate's overlay.
 */

import type { EpgIndex, NowNext, Programme } from "./iptv-types";

/** Find the current + next programme for a channel at time `at` (epoch ms). */
export function nowNext(epg: EpgIndex, epgId: string, at: number = Date.now()): NowNext {
  const list = epg.get(epgId);
  if (!list || list.length === 0) return { current: null, next: null };

  let current: Programme | null = null;
  let next: Programme | null = null;
  for (let i = 0; i < list.length; i++) {
    const p = list[i];
    if (at >= p.start && at < p.stop) {
      current = p;
      next = list[i + 1] ?? null;
      break;
    }
    if (p.start > at) {
      next = p;
      break;
    }
  }
  return { current, next };
}

/** 0..1 progress through the current programme (for the info-bar bar). */
export function progressOf(p: Programme | null, at: number = Date.now()): number {
  if (!p || p.stop <= p.start) return 0;
  return Math.min(1, Math.max(0, (at - p.start) / (p.stop - p.start)));
}

/** "20:00 – 21:30" label for a programme. */
export function timeRange(p: Programme): string {
  return `${hhmm(p.start)} – ${hhmm(p.stop)}`;
}

export function hhmm(ms: number): string {
  const d = new Date(ms);
  return `${d.getHours().toString().padStart(2, "0")}:${d
    .getMinutes()
    .toString()
    .padStart(2, "0")}`;
}
