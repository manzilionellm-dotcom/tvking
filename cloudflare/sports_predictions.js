// =========================================================
//  sports_predictions.js — Pronostics des fans, côté SERVEUR
// =========================================================
//  Demande du propriétaire (06/09/2026) : « sondages et prédictions en
//  direct » dans le coin Sport, sur le téléphone ET la TV.
//
//  CE QUE C'EST : avant un match, chaque appareil peut dire qui va
//  gagner — domicile, nul, extérieur. Tout le monde voit ensuite le
//  pourcentage des fans pour chaque camp, puis le résultat tranche.
//
//  CE QUE CE N'EST PAS, et c'est important pour les magasins : aucun
//  argent, aucun gain, aucun classement entre personnes. C'est un
//  sondage entre spectateurs, pas un pari. Le code ne connaît ni compte
//  utilisateur ni identité : seule l'adresse MAC virtuelle de l'appareil
//  (déjà utilisée par toutes les autres routes) sert de clé, pour qu'un
//  appareil ne compte qu'UNE voix par match.
//
//  RÈGLES, toutes vérifiées par sports_predictions.smoke.mjs :
//    1. un appareil = une voix par match ; revoter REMPLACE (pas d'empilage) ;
//    2. le choix est fermé : home | draw | away, rien d'autre n'entre en base ;
//    3. après le coup d'envoi, plus de vote (le client envoie l'heure du
//       coup d'envoi qu'il connaît ; sans enjeu financier, cette
//       auto-déclaration suffit — un tricheur ne gagne que de fausser un
//       sondage auquel il participe) ;
//    4. la lecture ne renvoie que des COMPTES, jamais la liste des
//       appareils : personne ne peut savoir qui a voté quoi.
//
//  Les helpers HTTP (json, badRequest) sont passés en paramètre, comme
//  dans device_profiles.js : ce module ne connaît que la logique métier.
// =========================================================

export const PICKS = Object.freeze(['home', 'draw', 'away']);

/// Identifiant de match TheSportsDB : des chiffres, parfois des lettres.
/// Borné pour qu'aucune chaîne libre n'atteigne la base.
const MATCH_ID_RE = /^[A-Za-z0-9_-]{1,40}$/;

/// Adresse MAC virtuelle « MK:XX:… » (ou une vraie MAC) — même forme que
/// partout ailleurs dans le Worker.
const MAC_RE = /^[A-Za-z0-9:]{6,40}$/;

export function validPick(p) {
  return PICKS.includes(String(p || ''));
}

export function validMatchId(id) {
  return MATCH_ID_RE.test(String(id || ''));
}

export function validMac(mac) {
  return MAC_RE.test(String(mac || ''));
}

/// Un vote est recevable tant que le coup d'envoi n'est pas passé.
/// `kickoffMs` absent (client ancien, match sans horaire) → on accepte :
/// mieux vaut un vote de trop qu'un sondage vide par excès de zèle.
export function voteOpen(nowMs, kickoffMs) {
  if (!Number.isFinite(kickoffMs) || kickoffMs <= 0) return true;
  return nowMs < kickoffMs;
}

/// Comptes → pourcentages ENTIERS qui font toujours 100 (méthode du
/// plus grand reste). Sans elle, 33/33/33 laisse 1 % dans la nature et
/// l'écran affiche une somme qui ne tombe pas juste — le genre de détail
/// qu'un client remarque et qui décrédibilise tout le reste.
export function percentages(counts) {
  const keys = PICKS;
  const total = keys.reduce((s, k) => s + (Number(counts[k]) || 0), 0);
  const out = { home: 0, draw: 0, away: 0 };
  if (total <= 0) return out;
  const exact = keys.map((k) => ((Number(counts[k]) || 0) * 100) / total);
  const floors = exact.map((x) => Math.floor(x));
  let rest = 100 - floors.reduce((s, x) => s + x, 0);
  // Les restes les plus grands reçoivent le point manquant, en ordre.
  const order = keys
    .map((k, i) => ({ k, i, r: exact[i] - floors[i] }))
    .sort((a, b) => b.r - a.r || a.i - b.i);
  for (const o of order) {
    out[o.k] = floors[o.i] + (rest > 0 ? 1 : 0);
    if (rest > 0) rest--;
  }
  return out;
}

export async function ensurePredictionsTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS match_predictions (' +
      'match_id TEXT NOT NULL, mac TEXT NOT NULL, pick TEXT NOT NULL, ' +
      'kickoff_ms INTEGER, at INTEGER NOT NULL, ' +
      'PRIMARY KEY (match_id, mac))',
  ).run();
}

async function tallyFor(env, matchId) {
  const rows = await env.DB.prepare(
    'SELECT pick, COUNT(*) AS n FROM match_predictions WHERE match_id = ? GROUP BY pick',
  ).bind(matchId).all();
  const counts = { home: 0, draw: 0, away: 0 };
  for (const r of (rows && rows.results) || []) {
    if (validPick(r.pick)) counts[r.pick] = Number(r.n) || 0;
  }
  const total = counts.home + counts.draw + counts.away;
  return { counts, total, percent: percentages(counts) };
}

async function mineFor(env, matchId, mac) {
  if (!mac) return null;
  const row = await env.DB.prepare(
    'SELECT pick FROM match_predictions WHERE match_id = ? AND mac = ?',
  ).bind(matchId, mac).first();
  return row && validPick(row.pick) ? row.pick : null;
}

/// GET /api/sports/predict/:matchId?mac=…
///  → { match, total, counts, percent, mine }
export async function handlePredictionGet(env, matchId, url, { json, badRequest }) {
  if (!validMatchId(matchId)) return badRequest('bad match id');
  if (!env.DB) return json({ error: 'storage unavailable' }, 503);
  await ensurePredictionsTable(env);
  const mac = (url.searchParams.get('mac') || '').trim();
  const t = await tallyFor(env, matchId);
  return json({
    match: matchId,
    total: t.total,
    counts: t.counts,
    percent: t.percent,
    mine: validMac(mac) ? await mineFor(env, matchId, mac) : null,
  });
}

/// POST /api/sports/predict  { mac, match, pick, kickoff? }
///  → même corps que le GET, ou 409 si le coup d'envoi est passé.
export async function handlePredictionPost(env, request, { json, badRequest }) {
  if (!env.DB) return json({ error: 'storage unavailable' }, 503);
  let body = {};
  try { body = await request.json(); } catch (_) { return badRequest('invalid JSON'); }
  const mac = String(body.mac || '').trim();
  const matchId = String(body.match || '').trim();
  const pick = String(body.pick || '').trim();
  if (!validMac(mac)) return badRequest('bad mac');
  if (!validMatchId(matchId)) return badRequest('bad match id');
  if (!validPick(pick)) return badRequest('bad pick');
  // `kickoff` : ISO 8601 ou millisecondes. Illisible → ignoré (vote ouvert).
  let kickoffMs = null;
  if (body.kickoff !== undefined && body.kickoff !== null && body.kickoff !== '') {
    const k = typeof body.kickoff === 'number'
      ? body.kickoff : Date.parse(String(body.kickoff));
    if (Number.isFinite(k)) kickoffMs = k;
  }
  const now = Date.now();
  if (!voteOpen(now, kickoffMs)) {
    return json({ error: 'closed', message: 'Le match a commencé.' }, 409);
  }
  await ensurePredictionsTable(env);
  await env.DB.prepare(
    'INSERT INTO match_predictions (match_id, mac, pick, kickoff_ms, at) ' +
      'VALUES (?, ?, ?, ?, ?) ' +
      'ON CONFLICT(match_id, mac) DO UPDATE SET pick = excluded.pick, ' +
      'kickoff_ms = excluded.kickoff_ms, at = excluded.at',
  ).bind(matchId, mac, pick, kickoffMs, now).run();
  const t = await tallyFor(env, matchId);
  return json({
    match: matchId,
    total: t.total,
    counts: t.counts,
    percent: t.percent,
    mine: pick,
  });
}
