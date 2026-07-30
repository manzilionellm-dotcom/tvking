/*
 * Extended M3U parser (the "master subscription line" format).
 *
 * Tolerant by design: provider playlists are hand-rolled text with CRLF, BOMs,
 * stray blank lines, duplicate names and directives nobody documents. A parse
 * error would take the whole channel map down, so unknown directives are
 * skipped and only genuinely unusable entries are dropped — with a count, so
 * the operator sees that something was ignored.
 */

export interface M3uEntry {
  /** Stable channel id used in edge URLs: tvg-id when present, else a slug. */
  id: string;
  name: string;
  url: string;
  group?: string;
  logo?: string;
  /** Raw `#EXTINF` attributes, lower-cased keys. */
  attributes: Readonly<Record<string, string>>;
}

export interface M3uPlaylist {
  entries: M3uEntry[];
  byId: Map<string, M3uEntry>;
  /** Lines that looked like entries but had no usable URL. */
  skipped: number;
}

const ATTRIBUTE = /([A-Za-z0-9_-]+)="([^"]*)"/g;

/** URL-safe, stable, collision-free channel id. */
export function slugify(value: string): string {
  const slug = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 96);
  return slug || "channel";
}

function parseAttributes(info: string): Record<string, string> {
  const attributes: Record<string, string> = {};
  ATTRIBUTE.lastIndex = 0;
  for (const match of info.matchAll(ATTRIBUTE)) {
    attributes[match[1].toLowerCase()] = match[2];
  }
  return attributes;
}

function displayName(info: string): string {
  // #EXTINF:<duration> <attributes>,<display name>
  const comma = info.lastIndexOf(",");
  return comma >= 0 ? info.slice(comma + 1).trim() : "";
}

export function parseM3u(text: string): M3uPlaylist {
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/);
  const entries: M3uEntry[] = [];
  const byId = new Map<string, M3uEntry>();
  let skipped = 0;

  let pending: { attributes: Record<string, string>; name: string } | null = null;
  let group: string | undefined;

  for (const raw of lines) {
    const line = raw.trim();
    if (line === "") continue;

    if (line.startsWith("#")) {
      const upper = line.toUpperCase();
      if (upper.startsWith("#EXTINF:")) {
        if (pending) skipped += 1; // an #EXTINF with no URL before the next one
        const info = line.slice("#EXTINF:".length);
        pending = { attributes: parseAttributes(info), name: displayName(info) };
      } else if (upper.startsWith("#EXTGRP:")) {
        group = line.slice("#EXTGRP:".length).trim() || undefined;
      }
      // #EXTM3U, #EXTVLCOPT, #KODIPROP, comments: not needed for routing.
      continue;
    }

    if (!pending) continue; // a bare URL with no #EXTINF is not addressable
    const { attributes, name } = pending;
    pending = null;

    const label = name || attributes["tvg-name"] || attributes["tvg-id"] || "";
    const base = attributes["tvg-id"] ? slugify(attributes["tvg-id"]) : slugify(label);
    let id = base;
    for (let n = 2; byId.has(id); n += 1) id = `${base}-${n}`;

    const entry: M3uEntry = {
      id,
      name: label || id,
      url: line,
      group: attributes["group-title"] || group,
      logo: attributes["tvg-logo"] || undefined,
      attributes,
    };
    entries.push(entry);
    byId.set(id, entry);
  }

  if (pending) skipped += 1;
  return { entries, byId, skipped };
}
