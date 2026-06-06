/*
 * M3U / M3U8 playlist parser.
 *
 * Handles the extended M3U format used by IPTV providers (Xtream `get.php` and
 * plain M3U exports):
 *
 *   #EXTM3U
 *   #EXTINF:-1 tvg-id="france24.fr" tvg-logo="http://…/f24.png" group-title="News",France 24
 *   http://server/live/france24.m3u8
 *
 * We read the `#EXTINF` attribute soup + the trailing display name, then the
 * next non-comment line is the stream URL. Nothing is fetched here — this is a
 * pure function so it can be unit-reasoned and reused on client or server.
 */

import type { Channel, ChannelGroup, Playlist } from "./iptv-types";

/** Pull `key="value"` attributes out of an #EXTINF line. */
function parseAttrs(line: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /([a-zA-Z0-9_-]+)="([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(line))) attrs[m[1].toLowerCase()] = m[2];
  return attrs;
}

/** Route-safe slug (ASCII, lowercase, dash-separated). */
export function slugify(s: string): string {
  return (
    s
      .normalize("NFD")
      .replace(/\p{Diacritic}/gu, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "x"
  );
}

const UNGROUPED = "Autres";

/**
 * Parse an extended M3U document into channels + groups (playlist order kept).
 * Channels without a usable URL are skipped.
 */
export function parseM3U(text: string): Playlist {
  const lines = text.split(/\r?\n/);
  const channels: Channel[] = [];
  const seenId = new Map<string, number>();

  let pending: { name: string; attrs: Record<string, string> } | null = null;

  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;

    if (line.startsWith("#EXTINF")) {
      const comma = line.indexOf(",");
      const name = comma >= 0 ? line.slice(comma + 1).trim() : "";
      pending = { name, attrs: parseAttrs(line) };
      continue;
    }

    // Other directives (#EXTM3U, #EXTVLCOPT, #EXTGRP, …) — skip, but #EXTGRP
    // can override the group when group-title is absent.
    if (line.startsWith("#")) {
      if (line.startsWith("#EXTGRP:") && pending) {
        pending.attrs["group-title"] ||= line.slice("#EXTGRP:".length).trim();
      }
      continue;
    }

    // A URL line: pair it with the pending #EXTINF (or a bare URL fallback).
    const url = line;
    const attrs = pending?.attrs ?? {};
    const displayName = pending?.name || attrs["tvg-name"] || `Chaîne ${channels.length + 1}`;
    const epgId = attrs["tvg-id"] || "";
    const group = (attrs["group-title"] || UNGROUPED).trim() || UNGROUPED;

    // Build a stable, unique id. Prefer tvg-id; de-dupe with a counter.
    const base = slugify(epgId || displayName);
    const n = (seenId.get(base) ?? 0) + 1;
    seenId.set(base, n);
    const id = n === 1 ? base : `${base}-${n}`;

    channels.push({
      id,
      epgId,
      number: channels.length + 1,
      name: displayName,
      logo: attrs["tvg-logo"] || undefined,
      group,
      url,
    });
    pending = null;
  }

  return { channels, groups: groupChannels(channels), total: channels.length };
}

/** Bucket channels by group-title, preserving first-seen group + channel order. */
export function groupChannels(channels: Channel[]): ChannelGroup[] {
  const order: string[] = [];
  const byName = new Map<string, Channel[]>();
  for (const ch of channels) {
    if (!byName.has(ch.group)) {
      byName.set(ch.group, []);
      order.push(ch.group);
    }
    byName.get(ch.group)!.push(ch);
  }
  return order.map((name) => ({ id: slugify(name), name, channels: byName.get(name)! }));
}
