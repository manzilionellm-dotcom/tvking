/*
 * Recherche intelligente de chaînes — l'utilisateur tape un mot (même vague, en
 * n'importe quelle langue) et les bonnes chaînes remontent. Tout est LOCAL et
 * instantané (aucun appel réseau, aucun coût) :
 *
 *  - normalisation insensible aux accents/casse/ponctuation (toutes écritures) ;
 *  - synonymes multilingues par thème (sport, infos, films, enfants, musique,
 *    docs) : taper « foot », « sport », « كرة », « 足球 »… fait remonter les
 *    chaînes dont le nom/catégorie contient bein, espn, dazn, eurosport… ;
 *  - score de pertinence (nom exact > début de nom > mot entier > sous-chaîne >
 *    thème), puis tri par numéro de chaîne.
 */

import type { Channel } from "./iptv-types";

export function normalize(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // accents latins
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ") // garde lettres/chiffres de TOUTES les écritures
    .trim();
}

/** Thèmes : `aliases` = ce que l'utilisateur tape ; `signals` = indices dans les noms/catégories. */
interface Category {
  aliases: string[];
  signals: string[];
}

const CATEGORIES: Category[] = [
  {
    aliases: [
      "sport", "sports", "foot", "football", "soccer", "futbol", "calcio", "fussball",
      "spor", "deporte", "deportes", "رياضة", "كرة", "كرة القدم", "спорт", "футбол",
      "体育", "足球", "球赛",
    ],
    signals: [
      "sport", "bein", "be in", "espn", "dazn", "eurosport", "sky sp", "rmc", "ssc",
      "match", "football", "futbol", "calcio", "arena", "premier", "league", "liga",
      "ligue", "goal", "ssport", "supersport", "canal sport", "fight", "ufc", "nba",
      "tennis", "golf", "f1", "motogp",
    ],
  },
  {
    aliases: [
      "news", "info", "infos", "actualite", "actualites", "noticias", "notizie",
      "nachrichten", "أخبار", "اخبار", "новости", "新闻", "haber", "haberler",
    ],
    signals: [
      "news", "info", "cnn", "bbc", "france 24", "france24", "al jazeera", "aljazeera",
      "sky news", "euronews", "i24", "lci", "bfm", "cnbc", "msnbc", "fox news",
      "rt", "trt", "cgtn", "arabiya", "العربية", "الجزيرة",
    ],
  },
  {
    aliases: [
      "movie", "movies", "film", "films", "cinema", "cine", "pelicula", "peliculas",
      "kino", "فيلم", "افلام", "أفلام", "кино", "фильм", "电影", "sinema",
    ],
    signals: [
      "cinema", "cine", "film", "movie", "mbc 2", "mbc2", "mbc max", "osn", "tnt",
      "paramount", "hbo", "canal cinema", "action", "thriller", "comedy", "drama",
      "max", "starz", "cinemax", "moviestar",
    ],
  },
  {
    aliases: [
      "kid", "kids", "enfant", "enfants", "ninos", "bambini", "kinder", "أطفال",
      "اطفال", "дети", "儿童", "cocuk", "cartoon", "dessin anime",
    ],
    signals: [
      "kids", "baby", "cartoon", "disney", "nick", "boomerang", "gulli", "junior",
      "toon", "teen", "piwi", "tiji", "spacetoon", "majid",
    ],
  },
  {
    aliases: ["music", "musique", "musica", "musik", "موسيقى", "музыка", "音乐", "muzik"],
    signals: ["music", "mtv", "trace", "clubbing", "hits", "vevo", "stingray", "mezzo", "nrj"],
  },
  {
    aliases: [
      "doc", "docs", "documentary", "documentaire", "documental", "وثائقي", "وثائقية",
      "документаль", "纪录", "belgesel",
    ],
    signals: [
      "discovery", "nat geo", "national geographic", "history", "histoire", "animal",
      "planet", "doc", "science", "nature", "investigation", "geo",
    ],
  },
];

const NORM_CACHE = new WeakMap<Channel, string>();
function haystack(c: Channel): string {
  let h = NORM_CACHE.get(c);
  if (h === undefined) {
    h = `${normalize(c.name)} ${normalize(c.group)}`;
    NORM_CACHE.set(c, h);
  }
  return h;
}

function scoreChannel(c: Channel, q: string, tokens: string[], catSignals: string[]): number {
  const name = normalize(c.name);
  const hay = haystack(c);
  let s = 0;

  if (name === q) s += 100;
  else if (name.startsWith(q)) s += 45;
  if (q.length >= 2 && hay.includes(q)) s += 20;

  for (const tok of tokens) {
    if (tok.length < 1) continue;
    if (new RegExp(`(^| )${tok}( |$)`).test(hay)) s += 9; // mot entier
    else if (hay.includes(tok)) s += 3; // sous-chaîne
  }

  for (const sig of catSignals) {
    if (hay.includes(sig)) {
      s += 14;
      break; // un seul bonus de thème par chaîne
    }
  }
  return s;
}

/** Recherche intelligente : renvoie les chaînes les plus pertinentes, triées. */
export function smartSearch(channels: Channel[], query: string, limit = 80): Channel[] {
  const q = normalize(query);
  if (q.length < 1) return [];
  const tokens = q.split(" ").filter(Boolean);

  // Thèmes déclenchés par la requête → on agrège leurs "signals".
  const catSignals: string[] = [];
  for (const cat of CATEGORIES) {
    const hit = cat.aliases.some((a) => q.includes(a) || tokens.includes(a) || a.includes(q));
    if (hit) catSignals.push(...cat.signals);
  }

  const scored: { c: Channel; s: number }[] = [];
  for (const c of channels) {
    const s = scoreChannel(c, q, tokens, catSignals);
    if (s > 0) scored.push({ c, s });
  }
  scored.sort((a, b) => b.s - a.s || a.c.number - b.c.number);
  return scored.slice(0, limit).map((x) => x.c);
}
