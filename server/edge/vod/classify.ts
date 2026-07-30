/*
 * Turning provider playlist lines into catalogue entries.
 *
 * Provider VOD lines are not metadata, they are decorated filenames:
 *   "FR - Le Grand Bleu (1988) [MULTI 1080p]"
 *   "EN | Breaking Bad S05E14 4K"
 * The heuristics below strip the decoration so that the same work coming from
 * four different playlists collapses to ONE catalogue title — which is the
 * whole point of aggregating. They are deliberately conservative: a title that
 * cannot be parsed keeps its raw name rather than being mangled into a wrong
 * match, because a duplicate is a cosmetic problem and a bad merge is a
 * corrupted catalogue.
 */

export type VodKind = "movie" | "series";

export interface ClassifiedItem {
  kind: VodKind;
  /** Cleaned display title. */
  title: string;
  /** Dedup key: lower-case, accent- and punctuation-free. */
  normalized: string;
  year: number;
  quality: string | null;
  container: string | null;
  season: number | null;
  episode: number | null;
  category: string;
}

/** Xtream-style paths are the strongest signal about what a line is. */
const MOVIE_PATH = /\/movie\//i;
const SERIES_PATH = /\/series\//i;
const EPISODE_RE = /\bS(\d{1,2})[\s._-]?E(\d{1,3})\b/i;
const ALT_EPISODE_RE = /\b(\d{1,2})x(\d{2})\b/;
const YEAR_RE = /\((19\d{2}|20\d{2})\)|\b(19\d{2}|20\d{2})\b/;
const QUALITY_RE =
  /\b(4K|UHD|2160P|1080P|720P|480P|HDRIP|WEBRIP|WEB-DL|BLURAY|BRRIP|DVDRIP|HDTV|CAM|TS|SD|HD|FHD|MULTI|VOSTFR|VOST|VF|VFF|VFQ|TRUEFRENCH|SUBFRENCH)\b/gi;
const CONTAINER_RE = /\.(mkv|mp4|avi|m4v|mov|ts)(?:$|\?)/i;
/**
 * `.ts` is deliberately absent here: it is BOTH a VOD container and the normal
 * extension of a live MPEG-TS channel, so treating it as a VOD signal files
 * every live channel in the film library. VOD `.ts` files still work — they are
 * recognised by their `/movie/` path, which is unambiguous.
 */
const VOD_CONTAINER_RE = /\.(mkv|mp4|avi|m4v|mov)(?:$|\?)/i;
const LIVE_PATH = /\/live\//i;
/** Leading provider tags: "FR - ", "EN | ", "|AR| ", "AR: ". */
const LEADING_TAG_RE = /^\s*[|[(]?\s*[A-Z]{2,5}\s*[|\])]?\s*[-–:|]\s*/;

export function stripAccents(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

/** Comparison key: what makes "the same film" the same. */
export function normalizeTitle(value: string): string {
  return stripAccents(value)
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/['’`]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\b(the|le|la|les|a|an|un|une|el|il)\b/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function detectKind(name: string, url: string, group: string): VodKind {
  if (SERIES_PATH.test(url)) return "series";
  if (MOVIE_PATH.test(url)) return "movie";
  if (EPISODE_RE.test(name) || ALT_EPISODE_RE.test(name)) return "series";
  if (/\b(series|serie|séries|série|tv ?shows?)\b/i.test(group)) return "series";
  return "movie";
}

/**
 * Category from the provider's group, with the decoration providers add to it
 * ("VOD | ACTION (FR)" → "Action"). Falls back to a per-kind default so nothing
 * lands in a nameless bucket.
 */
export function normalizeCategory(group: string | undefined, kind: VodKind): string {
  const raw = (group ?? "")
    .replace(/\b(vod|film[s]?|movies?|series|séries|serie|s[ée]ries?)\b/gi, " ")
    .replace(/[|[\]()]/g, " ")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!raw) return kind === "series" ? "Séries" : "Films";
  return raw
    .toLowerCase()
    .split(" ")
    .map((word) => (word.length > 2 ? word[0].toUpperCase() + word.slice(1) : word.toUpperCase()))
    .join(" ");
}

export function classify(input: {
  name: string;
  url: string;
  group?: string;
  attributes?: Readonly<Record<string, string>>;
}): ClassifiedItem {
  const group = input.group ?? "";
  const kind = detectKind(input.name, input.url, group);

  let title = input.name.replace(LEADING_TAG_RE, "").trim();

  const episodeMatch = EPISODE_RE.exec(title) ?? ALT_EPISODE_RE.exec(title);
  let season: number | null = null;
  let episode: number | null = null;
  if (episodeMatch) {
    season = Number(episodeMatch[1]);
    episode = Number(episodeMatch[2]);
    // A series title is the SHOW, not the episode: everything from the episode
    // marker on is per-episode noise.
    title = title.slice(0, episodeMatch.index).trim();
  }

  const yearMatch = YEAR_RE.exec(title);
  const year = yearMatch ? Number(yearMatch[1] ?? yearMatch[2]) : 0;
  if (yearMatch) title = title.replace(yearMatch[0], " ");

  const qualities = title.match(QUALITY_RE);
  const quality = qualities ? qualities[0].toUpperCase() : null;
  title = title.replace(QUALITY_RE, " ");

  const containerMatch = CONTAINER_RE.exec(input.url);
  const container = containerMatch ? containerMatch[1].toLowerCase() : null;

  title = title
    .replace(/[[\]()]/g, " ")
    .replace(/\s*[-–|]\s*$/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!title) title = input.name.trim();

  return {
    kind,
    title,
    normalized: normalizeTitle(title),
    year,
    quality,
    container,
    season,
    episode,
    category: normalizeCategory(group, kind),
  };
}

/** True when a playlist line looks like VOD rather than a live channel. */
export function looksLikeVod(input: { url: string; group?: string; name: string }): boolean {
  if (MOVIE_PATH.test(input.url) || SERIES_PATH.test(input.url)) return true;
  if (LIVE_PATH.test(input.url)) return false; // an explicit live path settles it
  if (VOD_CONTAINER_RE.test(input.url)) return true;
  return /\b(vod|film|movie|s[ée]rie|series)\b/i.test(input.group ?? "");
}
