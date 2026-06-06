/*
 * NOVA+ — IPTV domain model.
 *
 * Built to mirror what an Xtream/M3U + XMLTV source gives us, which is what the
 * reference app (TiViMate) consumes: a flat list of channels carrying group,
 * logo and stream URL (from the M3U `#EXTINF` attributes), plus a separate EPG
 * (XMLTV) keyed by `tvg-id`. See docs/NOVA-RECONSTRUCTION-TIVIMATE.md.
 */

/** A single live channel parsed from an M3U `#EXTINF` line. */
export interface Channel {
  /** Stable id used in routes/favorites — `tvg-id` when present, else a slug. */
  id: string;
  /** EPG id (`tvg-id`) used to join with XMLTV programmes; may be empty. */
  epgId: string;
  /** Display number (1-based order in the playlist) — TiViMate-style zapping. */
  number: number;
  name: string;
  /** Channel logo URL (`tvg-logo`), 1:1 per Android TV card spec. */
  logo?: string;
  /** Group / category (`group-title`) — drives the left rail. */
  group: string;
  /** The playable stream URL (HLS `.m3u8`, TS, etc.). */
  url: string;
}

/** Channels bucketed by their `group-title`, in playlist order. */
export interface ChannelGroup {
  /** Slug of the group name (route-safe). */
  id: string;
  name: string;
  channels: Channel[];
}

/** One EPG entry (XMLTV `<programme>`). Times are epoch ms. */
export interface Programme {
  channelEpgId: string;
  start: number;
  stop: number;
  title: string;
  desc?: string;
}

/** EPG indexed by channel `epgId`, each list sorted by start time. */
export type EpgIndex = Map<string, Programme[]>;

/** The fully parsed source: channels, their groups, and the EPG index. */
export interface Playlist {
  channels: Channel[];
  groups: ChannelGroup[];
  /** Total channels before any UI cap. */
  total: number;
}

/** Current + next programme for a channel (the now/next info bar). */
export interface NowNext {
  current: Programme | null;
  next: Programme | null;
}
