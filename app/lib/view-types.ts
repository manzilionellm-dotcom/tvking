/*
 * Lightweight, fully-serializable shapes passed from Server Components to the
 * interactive Client Components (channel browser, player, guide). We keep these
 * separate from the rich domain types so payloads stay small and JSON-safe.
 */

import type { Channel } from "./iptv-types";

/** Compact now/next entry for a channel, sent to the client for the info line. */
export interface NowNextLite {
  title: string;
  start: number;
  stop: number;
  nextTitle?: string;
}

/** now/next keyed by channel id (only channels with EPG data are included). */
export type NowNextMap = Record<string, NowNextLite>;

export type { Channel };
