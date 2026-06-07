/*
 * Détection d'événements en direct / à venir à partir du guide (EPG) — base des
 * alertes in-app « grand match / événement ». 100 % local, sans réseau.
 *
 *  - liveEvents()     : chaînes dont le programme EN COURS ressemble à un
 *                       événement sportif (pour le rail « En direct »).
 *  - upcomingAlerts() : événements qui COMMENCENT bientôt (sport sur n'importe
 *                       quelle chaîne, ou n'importe quel programme sur une
 *                       chaîne FAVORITE) — pour les notifications in-app.
 */

import type { Channel, EpgIndex, Programme } from "./iptv-types";
import { normalize } from "./search";

// Mots qui trahissent un événement (sport surtout) dans un titre EPG.
const EVENT_WORDS = [
  "football", "foot", "soccer", "match", "vs", "ligue", "liga", "league", "serie a",
  "champions", "uefa", "europa", "coupe", "cup", "derby", "clasico", "basket",
  "basketball", "nba", "tennis", "atp", "wta", "roland", "wimbledon", "grand prix",
  "formula", "formule", "f1", "motogp", "boxing", "boxe", "ufc", "mma", "rugby",
  "cricket", "handball", "volley", "golf", "final", "finale", "demi finale",
  "quart", "playoff", "playoffs", "كرة", "مباراة", "دوري", "матч", "лига", "比赛", "联赛",
];

export interface LiveEvent {
  channel: Channel;
  programme: Programme;
}

/** Un titre de programme ressemble-t-il à un événement (sport) ? */
export function isEventTitle(title: string): boolean {
  const t = normalize(title);
  if (!t) return false;
  return EVENT_WORDS.some((w) => t.includes(w));
}

/** Programme en cours d'une chaîne (now ∈ [start, stop)). */
function currentProgramme(epg: EpgIndex, epgId: string, now: number): Programme | null {
  if (!epgId) return null;
  const list = epg.get(epgId);
  if (!list) return null;
  for (const p of list) {
    if (p.start <= now && now < p.stop) return p;
    if (p.start > now) break; // listes triées par début
  }
  return null;
}

/** Prochain programme d'une chaîne démarrant dans (now, now+windowMs]. */
function nextWithin(epg: EpgIndex, epgId: string, now: number, windowMs: number): Programme | null {
  if (!epgId) return null;
  const list = epg.get(epgId);
  if (!list) return null;
  for (const p of list) {
    if (p.start > now) return p.start <= now + windowMs ? p : null;
  }
  return null;
}

/** Chaînes dont le programme EN COURS est un événement sportif. */
export function liveEvents(channels: Channel[], epg: EpgIndex, now: number, limit = 24): LiveEvent[] {
  if (epg.size === 0) return [];
  const out: LiveEvent[] = [];
  for (const c of channels) {
    const p = currentProgramme(epg, c.epgId, now);
    if (p && isEventTitle(p.title)) out.push({ channel: c, programme: p });
    if (out.length >= limit) break;
  }
  return out;
}

/**
 * Événements démarrant bientôt : sport (toute chaîne) OU tout programme sur une
 * chaîne favorite. Triés par heure de début. Sert aux notifications in-app.
 */
export function upcomingAlerts(
  channels: Channel[],
  epg: EpgIndex,
  favoriteIds: Set<string>,
  now: number,
  windowMs = 12 * 60_000,
  limit = 12,
): LiveEvent[] {
  if (epg.size === 0) return [];
  const out: LiveEvent[] = [];
  for (const c of channels) {
    const p = nextWithin(epg, c.epgId, now, windowMs);
    if (!p) continue;
    if (favoriteIds.has(c.id) || isEventTitle(p.title)) out.push({ channel: c, programme: p });
  }
  out.sort((a, b) => a.programme.start - b.programme.start);
  return out.slice(0, limit);
}

/** Clé stable d'un événement (pour ne pas notifier deux fois). */
export function eventKey(e: LiveEvent): string {
  return `${e.channel.id}@${e.programme.start}`;
}
