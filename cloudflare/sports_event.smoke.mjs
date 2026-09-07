// =========================================================
//  sports_event.smoke.mjs — La fiche d'un match, côté serveur
// =========================================================
//  On fait tourner LE VRAI code (worker.js → sports_event.js) avec un
//  `fetch` simulé qui rejoue les réponses RÉELLES mesurées le 07/09 sur
//  Arsenal–Chelsea (formes de champs exactes). Ce qui est verrouillé :
//
//    1. VALIDATION : un identifiant qui n'est pas un nombre → 400, aucun
//       appel amont ;
//    2. MAPPAGE : « Corner Kicks 5–3 » ressort en {name, home:5, away:3} ;
//       un but de l'extérieur a home:false ; un remplaçant est marqué ;
//       « NULL » (chaîne) devient vide, jamais le mot « NULL » à l'écran ;
//    3. RÉSILIENCE : un bloc amont en 429 ne fait pas échouer la fiche,
//       il arrive vide avec available:false ;
//    4. CACHE : deux lectures dans la minute = un seul jeu d'appels amont.
//
//  Exécution : node cloudflare/sports_event.smoke.mjs
// =========================================================
import worker from './worker.js';

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

const upstream = {
  event: { events: [{ idEvent: '2494022', strEvent: 'Arsenal vs Chelsea', strHomeTeam: 'Arsenal', strAwayTeam: 'Chelsea', intHomeScore: '2', intAwayScore: '1', strStatus: 'FT', strLeague: 'English Premier League', strSport: 'Soccer', strVenue: 'Emirates Stadium', strResult: 'Arsenal recovered…', strTimestamp: '2026-09-06T15:30:00', strThumb: 'https://x/t.jpg', strHomeFormation: null }] },
  stats: { eventstats: [
    { strStat: 'Corner Kicks', intHome: '5', intAway: '3' },
    { strStat: 'Ball Possession', intHome: '55', intAway: '45' },
    { strStat: 'Yellow Cards', intHome: '2', intAway: '4' },
  ] },
  timeline: { timeline: [
    { intTime: '25', strTimeline: 'Goal', strTimelineDetail: 'Normal Goal', strPlayer: 'Kai Havertz', strHome: 'Yes', strTeam: 'Arsenal', strAssist: 'Declan Rice', strComment: 'NULL' },
    { intTime: '2', strTimeline: 'Goal', strTimelineDetail: 'Normal Goal', strPlayer: 'Morgan Rogers', strHome: 'No', strTeam: 'Chelsea', strAssist: 'Jorrel Hato', strComment: 'NULL' },
    { intTime: '14', strTimeline: 'Card', strTimelineDetail: 'Yellow Card', strPlayer: 'João Pedro', strHome: 'No', strTeam: 'Chelsea', strComment: 'Time Wasting' },
  ] },
  lineup: { lineup: [
    { strPlayer: 'David Raya', strHome: 'Yes', strPosition: 'Goalkeeper', strSubstitute: 'No', intSquadNumber: '1', strThumb: '' },
    { strPlayer: 'Emiliano Martinez', strHome: 'No', strPosition: 'Goalkeeper', strSubstitute: 'No', intSquadNumber: '1', strThumb: '' },
    { strPlayer: 'Remplaçant Test', strHome: 'Yes', strPosition: 'Centre-Forward', strSubstitute: 'Yes', intSquadNumber: '19', strThumb: '' },
  ] },
};

let calls = [];
let failStats = false;
globalThis.fetch = async (url) => {
  const u = String(url);
  calls.push(u);
  const body = (o) => new Response(JSON.stringify(o), { status: 200, headers: { 'content-type': 'application/json' } });
  if (u.includes('lookupevent.php')) return body(upstream.event);
  if (u.includes('lookupeventstats.php')) return failStats ? new Response('rate', { status: 429 }) : body(upstream.stats);
  if (u.includes('lookuptimeline.php')) return body(upstream.timeline);
  if (u.includes('lookuplineup.php')) return body(upstream.lineup);
  return new Response('nope', { status: 404 });
};

const env = { SPORTSDB_KEY: 'k' };
const call = (path) => worker.fetch(new Request('https://app.example' + path), env, { waitUntil() {} });

console.log('1. validation');
{
  calls = [];
  const r = await call('/api/sports/event/abc');
  ok(r.status === 400, 'identifiant non numérique → 400');
  ok(calls.length === 0, 'aucun appel amont pour un id invalide');
}

console.log('2. mappage');
{
  calls = [];
  const r = await call('/api/sports/event/2494022');
  ok(r.status === 200, 'fiche servie');
  const j = await r.json();
  ok(calls.length === 4 && calls.every((u) => u.includes('/k/')), 'quatre appels amont, avec la clé du Worker');
  ok(j.event && j.event.home === 'Arsenal' && j.event.homeScore === '2', 'événement : équipes et score');
  ok(j.event.homeFormation === '', 'null amont → chaîne vide, jamais « null »');
  const corners = j.stats.find((x) => x.name === 'Corner Kicks');
  ok(corners && corners.home === 5 && corners.away === 3, 'corners 5–3 en NOMBRES');
  ok(j.timeline[0].minute === 2 && j.timeline[0].home === false, 'chronologie triée par minute, but extérieur home:false');
  ok(j.timeline[0].comment === '', '« NULL » amont → vide (jamais le mot NULL à l\'écran)');
  ok(j.timeline[2].assist === 'Declan Rice', 'la passe décisive est conservée (25e, après tri)');
  ok(j.lineup.home.length === 2 && j.lineup.away.length === 1, 'compositions réparties domicile / extérieur');
  ok(j.lineup.home.find((p) => p.name === 'Remplaçant Test').substitute === true, 'remplaçant marqué');
  ok(j.available.stats === true && j.available.lineup === true, 'blocs déclarés disponibles');
}

console.log('3. cache 60 s');
{
  calls = [];
  const r = await call('/api/sports/event/2494022');
  ok(r.status === 200 && calls.length === 0, 'seconde lecture servie du cache, zéro appel amont');
}

console.log('4. un bloc amont en panne ne casse pas la fiche');
{
  failStats = true;
  calls = [];
  const r = await call('/api/sports/event/2494023');
  const j = await r.json();
  ok(r.status === 200, 'fiche servie malgré le 429 des stats');
  ok(j.stats.length === 0 && j.available.stats === false, 'stats vides ET déclarées indisponibles');
  ok(j.timeline.length === 3 && j.available.timeline === true, 'la chronologie, elle, est là');
  failStats = false;
}

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail ? 1 : 0);
