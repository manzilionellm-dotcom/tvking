/*
 * XMLTV (EPG) parser — the schedule source TiViMate joins to channels by tvg-id.
 *
 * XMLTV looks like:
 *   <programme start="20260606200000 +0000" stop="20260606213000 +0000"
 *              channel="france24.fr">
 *     <title>Le journal</title>
 *     <desc>…</desc>
 *   </programme>
 *
 * We avoid a heavy XML dependency: a focused regex sweep over `<programme>`
 * blocks is robust enough for XMLTV (no nested programmes) and fast on the
 * large EPG dumps providers return. Times parse to epoch ms.
 */

import type { EpgIndex, Programme } from "./iptv-types";

/** Parse an XMLTV timestamp: `YYYYMMDDHHMMSS [+-]HHMM` (offset optional). */
export function parseXmltvTime(s: string): number {
  const m = s
    .trim()
    .match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?(?:\s*([+-]\d{4}))?/);
  if (!m) return NaN;
  const [, y, mo, d, h, mi, se, tz] = m;
  // Build as UTC, then apply the explicit offset (default UTC).
  let ms = Date.UTC(+y, +mo - 1, +d, +h, +mi, se ? +se : 0);
  if (tz) {
    const sign = tz[0] === "-" ? -1 : 1;
    const offMin = sign * (parseInt(tz.slice(1, 3), 10) * 60 + parseInt(tz.slice(3, 5), 10));
    ms -= offMin * 60_000;
  }
  return ms;
}

function decodeEntities(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n))
    .trim();
}

function firstTag(block: string, tag: string): string | undefined {
  const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, "i"));
  return m ? decodeEntities(m[1]) : undefined;
}

/**
 * Parse XMLTV into an index keyed by channel id, each programme list sorted by
 * start. Only channels in `wanted` are kept (the EPG dumps are huge; keeping
 * only channels we actually have keeps memory sane).
 */
export function parseXmltv(text: string, wanted?: Set<string>): EpgIndex {
  const index: EpgIndex = new Map();
  const re = /<programme\b([^>]*)>([\s\S]*?)<\/programme>/gi;
  let m: RegExpExecArray | null;

  while ((m = re.exec(text))) {
    const attrs = m[1];
    const body = m[2];
    const chMatch = attrs.match(/channel="([^"]*)"/i);
    if (!chMatch) continue;
    const channelEpgId = chMatch[1];
    if (wanted && !wanted.has(channelEpgId)) continue;

    const startMatch = attrs.match(/start="([^"]*)"/i);
    const stopMatch = attrs.match(/stop="([^"]*)"/i);
    if (!startMatch) continue;
    const start = parseXmltvTime(startMatch[1]);
    const stop = stopMatch ? parseXmltvTime(stopMatch[1]) : start + 30 * 60_000;
    if (Number.isNaN(start)) continue;

    const prog: Programme = {
      channelEpgId,
      start,
      stop,
      title: firstTag(body, "title") || "Programme",
      desc: firstTag(body, "desc"),
    };
    const list = index.get(channelEpgId);
    if (list) list.push(prog);
    else index.set(channelEpgId, [prog]);
  }

  for (const list of index.values()) list.sort((a, b) => a.start - b.start);
  return index;
}
