/*
 * Local catalogue search — pure, so the matching contract is unit-testable.
 *
 * The research (docs/RESEARCH-TV-UX.md §5) is explicit: TV search is secondary
 * (remote text entry is painful) but it must WORK — the field used to be purely
 * decorative (backlog B4). Matching is accent- and case-insensitive because a
 * D-pad keyboard has no accented keys: typing "athletisme" must find
 * "Athlétisme".
 *
 * Ranking, best first: title prefix > title word prefix > title substring >
 * metadata (league, instructor, level, subtitle, topics). Ties keep catalogue
 * order, which puts the most relevant items to the left of a row (Netflix
 * convention).
 */

import type { MediaItem } from "./data";

/** Lowercase, strip diacritics, collapse whitespace. */
export function normalize(input: string): string {
  return input
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // combining diacritics left by NFD
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

/** Searchable text of an item: title first, then its facets/metadata. */
export function haystack(item: MediaItem): { title: string; meta: string } {
  const meta = [
    item.subtitle,
    item.league,
    item.instructor,
    item.level,
    item.duration,
    ...(item.topics ?? []),
  ]
    .filter(Boolean)
    .join(" ");
  return { title: normalize(item.title), meta: normalize(meta) };
}

/** Lower is better; null when the item does not match at all. */
export function score(item: MediaItem, query: string): number | null {
  const q = normalize(query);
  if (!q) return null;
  const { title, meta } = haystack(item);
  if (title.startsWith(q)) return 0;
  if (title.split(" ").some((w) => w.startsWith(q))) return 1;
  if (title.includes(q)) return 2;
  if (meta.split(" ").some((w) => w.startsWith(q))) return 3;
  if (meta.includes(q)) return 4;
  return null;
}

/** Ranked matches. An empty/whitespace query yields no results (not everything). */
export function searchItems(items: readonly MediaItem[], query: string): MediaItem[] {
  const scored: { item: MediaItem; s: number; i: number }[] = [];
  items.forEach((item, i) => {
    const s = score(item, query);
    if (s !== null) scored.push({ item, s, i });
  });
  return scored.sort((a, b) => a.s - b.s || a.i - b.i).map((x) => x.item);
}
