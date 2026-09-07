// =========================================================
//  sports_event.js — La FICHE d'un match, côté SERVEUR
// =========================================================
//  Demande du propriétaire (07/09/2026) : au clic sur une carte, une vue
//  détaillée « comme SofaScore » — résumé, stats, compositions, corners,
//  cartons.
//
//  TheSportsDB (clé payante) donne, pour un match, quatre choses :
//    • lookupevent      → statut, score, stade, résumé rédigé, vignette ;
//    • lookupeventstats → 16 lignes « possession, tirs, corners, cartons… » ;
//    • lookuptimeline   → buts, cartons, VAR, remplacements, avec la minute ;
//    • lookuplineup     → les 22 titulaires + remplaçants, poste et numéro.
//  Mesuré le 07/09 sur Arsenal–Chelsea (id 2494022) : 16 stats, 19
//  événements, 22 joueurs. C'est exactement ce dont l'écran a besoin.
//
//  CE QU'ELLE NE DONNE PAS, et on ne l'invente pas : les xG et les cartes
//  de chaleur. L'app affiche « non fourni par la source » sur ces deux
//  onglets, plutôt qu'un chiffre sorti de nulle part.
//
//  QUATRE appels amont pour UNE requête app : d'où un cache court par
//  isolate (60 s — un match en cours change de minute en minute). Un
//  appel amont raté ne fait pas échouer la fiche : chaque bloc arrive
//  avec son propre drapeau `available`, et l'écran dit ce qu'il n'a pas.
//
//  `base(env)` et `headers()` sont passés en paramètre (comme json /
//  badRequest) : ce module ne connaît pas la clé, seulement la logique.
// =========================================================

const EVENT_ID_RE = /^[0-9]{1,12}$/;
const TTL_MS = 60000;
const cache = new Map(); // id -> { at, data }

export function validEventId(id) {
  return EVENT_ID_RE.test(String(id || ''));
}

const s = (v) => (v === null || v === undefined || v === 'NULL' ? '' : String(v));
const n = (v) => {
  const x = parseInt(String(v), 10);
  return Number.isFinite(x) ? x : null;
};

export function mapEvent(e) {
  if (!e) return null;
  return {
    id: s(e.idEvent),
    name: s(e.strEvent),
    home: s(e.strHomeTeam),
    away: s(e.strAwayTeam),
    homeScore: e.intHomeScore === null || e.intHomeScore === undefined ? null : s(e.intHomeScore),
    awayScore: e.intAwayScore === null || e.intAwayScore === undefined ? null : s(e.intAwayScore),
    status: s(e.strStatus),
    progress: s(e.strProgress),
    league: s(e.strLeague),
    sport: s(e.strSport),
    venue: s(e.strVenue),
    country: s(e.strCountry),
    timestamp: s(e.strTimestamp),
    thumb: s(e.strThumb),
    homeBadge: s(e.strHomeTeamBadge),
    awayBadge: s(e.strAwayTeamBadge),
    homeFormation: s(e.strHomeFormation),
    awayFormation: s(e.strAwayFormation),
    summary: s(e.strResult),
  };
}

export function mapStat(x) {
  return { name: s(x.strStat), home: n(x.intHome), away: n(x.intAway) };
}

export function mapTimeline(x) {
  return {
    minute: n(x.intTime),
    type: s(x.strTimeline),          // Goal | Card | Var | subst | …
    detail: s(x.strTimelineDetail),  // Normal Goal | Yellow Card | …
    player: s(x.strPlayer),
    assist: s(x.strAssist),
    team: s(x.strTeam),
    home: s(x.strHome).toLowerCase() === 'yes',
    comment: s(x.strComment),
  };
}

export function mapPlayer(x) {
  return {
    name: s(x.strPlayer),
    position: s(x.strPosition),
    number: n(x.intSquadNumber),
    substitute: s(x.strSubstitute).toLowerCase() === 'yes',
    home: s(x.strHome).toLowerCase() === 'yes',
    thumb: s(x.strThumb),
  };
}

async function getJson(url, headers) {
  try {
    const r = await fetch(url, { headers });
    if (!r.ok) return null;
    return await r.json();
  } catch (_) {
    return null;
  }
}

/// GET /api/sports/event/:id
export async function handleSportsEvent(env, id, { json, badRequest, base, headers }) {
  if (!validEventId(id)) return badRequest('bad event id');
  const now = Date.now();
  const c = cache.get(id);
  if (c && now - c.at < TTL_MS) return json(c.data);

  const root = base(env);
  const h = headers();
  const q = encodeURIComponent(id);
  const [ev, st, tl, lu] = await Promise.all([
    getJson(`${root}/lookupevent.php?id=${q}`, h),
    getJson(`${root}/lookupeventstats.php?id=${q}`, h),
    getJson(`${root}/lookuptimeline.php?id=${q}`, h),
    getJson(`${root}/lookuplineup.php?id=${q}`, h),
  ]);

  const event = mapEvent(ev && Array.isArray(ev.events) ? ev.events[0] : null);
  const stats = (st && Array.isArray(st.eventstats) ? st.eventstats : []).map(mapStat)
    .filter((x) => x.name);
  const timeline = (tl && Array.isArray(tl.timeline) ? tl.timeline : []).map(mapTimeline)
    .sort((a, b) => (a.minute ?? 0) - (b.minute ?? 0));
  const players = (lu && Array.isArray(lu.lineup) ? lu.lineup : []).map(mapPlayer);

  const data = {
    id,
    event,
    stats,
    timeline,
    lineup: {
      home: players.filter((p) => p.home),
      away: players.filter((p) => !p.home),
    },
    // Chaque bloc dit s'il a été JOINT (≠ « vide ») : l'app distingue
    // « pas encore de stats » (match pas commencé) de « source muette ».
    available: { event: !!ev, stats: !!st, timeline: !!tl, lineup: !!lu },
    generated_at: new Date(now).toISOString(),
  };
  // Une fiche sans aucun bloc joint n'entre pas en cache : sinon un 429
  // passager figerait « rien » pendant 60 s pour tout le monde.
  if (ev || st || tl || lu) cache.set(id, { at: now, data });
  return json(data);
}
