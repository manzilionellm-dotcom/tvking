/*
 * M3U / M3U8 playlist parsing for the IPTV side ("Ma TV").
 *
 * Pure functions only — no network, no storage — so the whole IPTV ingestion
 * path is unit-testable. The parser is deliberately tolerant (real-world IPTV
 * playlists are messy): a missing #EXTM3U header, stray blank lines or unknown
 * #-directives never throw, they are just skipped. What comes out is only ever
 * well-formed channels.
 *
 * "Chaque lien est vérifié avant lecture": verifyUrl() is that check — a link
 * either passes (http/https, well-formed) and is marked prêt, or is rejected
 * with a human-readable reason shown next to the channel. Invalid links are
 * never sent to the player, so playback can never hang on them.
 */

export interface Channel {
  /** Stable id derived from position + name (used for resume + focus keys). */
  id: string;
  name: string;
  url: string;
  /** Optional logo URL (tvg-logo). */
  logo?: string;
  /** Optional group (group-title) — drives the grouped display. */
  group?: string;
}

export type LinkCheck = { ok: true } | { ok: false; reason: string };

/**
 * The pre-playback link check. Only http(s) URLs with a valid structure pass;
 * everything else is refused with a reason (shown in the UI, never a hang).
 */
export function verifyUrl(url: string): LinkCheck {
  const trimmed = url.trim();
  if (!trimmed) return { ok: false, reason: "Lien vide" };
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { ok: false, reason: "Adresse illisible" };
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return { ok: false, reason: "Protocole non pris en charge" };
  }
  if (!parsed.hostname) return { ok: false, reason: "Hôte manquant" };
  return { ok: true };
}

/** Extract a quoted or bare attribute (tvg-logo="…", group-title="…"). */
function attr(extinf: string, name: string): string | undefined {
  const m = extinf.match(new RegExp(`${name}="([^"]*)"`, "i"));
  return m?.[1] || undefined;
}

/** Channel display name: the text after the last comma of the #EXTINF line. */
function nameOf(extinf: string): string {
  const comma = extinf.lastIndexOf(",");
  return comma >= 0 ? extinf.slice(comma + 1).trim() : "";
}

/**
 * Parse M3U text into channels. Tolerant by design; only entries with a
 * non-empty name-or-url line pair are kept. Never throws.
 */
export function parseM3U(text: string): Channel[] {
  const channels: Channel[] = [];
  let pending: { name: string; logo?: string; group?: string } | null = null;

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;

    if (line.startsWith("#EXTINF")) {
      pending = {
        name: nameOf(line),
        logo: attr(line, "tvg-logo"),
        group: attr(line, "group-title"),
      };
      continue;
    }
    if (line.startsWith("#")) continue; // header or unknown directive

    // A URL line: pairs with the pending #EXTINF, or stands alone.
    const name = pending?.name || line;
    channels.push({
      id: `iptv-${channels.length}-${name.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 40)}`,
      name,
      url: line,
      logo: pending?.logo,
      group: pending?.group,
    });
    pending = null;
  }
  return channels;
}

/** Group channels by their group-title, preserving playlist order. */
export function groupChannels(channels: Channel[]): { group: string; channels: Channel[] }[] {
  const groups = new Map<string, Channel[]>();
  for (const ch of channels) {
    const key = ch.group || "Chaînes";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(ch);
  }
  return [...groups.entries()].map(([group, chs]) => ({ group, channels: chs }));
}
