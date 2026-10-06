// =========================================================
//  linkage.js — Contrat panel ↔ app (pur, testable)
// =========================================================
//  Aucun secret, aucune URL de flux. Fonctions déterministes
//  partagées par le Worker pour :
//    - ne pas répondre au heartbeat avant que la présence et
//      l'inventaire soient écrits (sinon le panel lit un état vieux) ;
//    - livrer CHAQUE annonce une fois (curseur `after`), pas
//      seulement la dernière ;
//    - ne pas ressusciter une liste effacée via le repli KV ;
//    - accepter une source seule OU un tableau (l'activation
//      envoie un objet, le trio envoie un tableau).
//
//  Le panel sonde au plus toutes les PANEL_POLL_MS (2 s) une
//  fois l'écriture commise. Le délai réel côté box dépend encore
//  du rythme de l'app installée (voir les tests de mesure).
// =========================================================

/// Le panel doit refléter un événement déjà commis en ≤ 2 secondes.
export const PANEL_POLL_MS = 2000;

/// Ancien sondage de la page « En ligne » (preuve du dépassement).
export const PANEL_POLL_MS_BEFORE = 30000;

/// Plafond d'annonces renvoyées par appel (le client avance le curseur).
export const ANNOUNCEMENT_PAGE = 30;

/**
 * Pire délai entre un événement commis et le prochain sondage du panel.
 * L'événement tombe juste après un tick : on attend un intervalle entier.
 */
export function worstCaseMirrorMs(pollMs) {
  if (!Number.isFinite(pollMs) || pollMs < 0) {
    throw new Error('pollMs invalide');
  }
  return pollMs;
}

/**
 * Une réponse de sondage plus ancienne qu'une réponse déjà affichée
 * ne doit pas écraser l'écran (requêtes qui se croisent).
 * `resultSeq` / `appliedSeq` sont des numéros croissants de requête.
 */
export function shouldApplyPollResult(resultSeq, appliedSeq) {
  return resultSeq >= appliedSeq;
}

/**
 * Simule la visibilité de la présence au moment où le heartbeat
 * renvoie sa réponse HTTP.
 *   defer=true  → écriture en arrière-plan (waitUntil) : au moment
 *                 de la réponse, la ligne n'est pas encore là.
 *   defer=false → on attend l'écriture avant de répondre.
 */
export async function heartbeatPresenceVisibility(store, event, { defer }) {
  let committed = false;
  const write = (async () => {
    await store.write(event);
    committed = true;
  })();
  if (!defer) await write;
  const visibleAtResponse = committed && !!store.read(event.mac);
  if (defer) await write;
  return {
    visibleAtResponse,
    visibleAfterFlush: !!store.read(event.mac),
  };
}

/** `created` ne doit être vrai qu'à la première fiche, pas à chaque ping. */
export function heartbeatCreatedFlag(existedBefore) {
  return !existedBefore;
}

function announcementInactive(row) {
  const a = row && row.active;
  return a === 0 || a === '0' || a === false;
}

function announcementFresh(row, now) {
  const exp = row ? row.expires_at : 0;
  if (exp === null || exp === undefined || exp === '' || exp === false) return true;
  const n = Number(exp);
  if (!Number.isFinite(n) || n === 0) return true;
  return n > now;
}

function announcementForCountry(row, country) {
  const c = String((row && row.country) || '').trim().toUpperCase();
  if (!c) return true;
  const want = String(country || '').trim().toUpperCase();
  return c === want;
}

export function isAnnouncementVisible(row, { now, country }) {
  if (!row || row.id == null) return false;
  if (announcementInactive(row)) return false;
  if (!announcementFresh(row, now)) return false;
  if (!announcementForCountry(row, country)) return false;
  const title = String(row.title || '');
  const body = String(row.body || '');
  return title.length > 0 || body.length > 0;
}

/**
 * File d'annonces.
 * `latest` = la plus récente encore visible (contrat historique de l'app,
 * qui ne lit qu'un objet). `pending` = toutes celles d'id > after, dans
 * l'ordre, sans doublon. Un client qui avance `after` ne perd rien et
 * ne reçoit pas deux fois le même id.
 */
export function selectAnnouncements(rows, { after = 0, now = Date.now(), country = '' } = {}) {
  const cursor = Number(after) || 0;
  const byId = new Map();
  for (const row of rows || []) {
    if (!isAnnouncementVisible(row, { now, country })) continue;
    const id = Number(row.id);
    if (!Number.isFinite(id)) continue;
    if (!byId.has(id)) byId.set(id, row);
  }
  const unique = [...byId.values()].sort((a, b) => Number(a.id) - Number(b.id));
  const latest = unique.length ? unique[unique.length - 1] : null;
  const pending = unique.filter((r) => Number(r.id) > cursor).slice(0, ANNOUNCEMENT_PAGE);
  return { latest, pending };
}

/** Ancien comportement : une seule ligne, la plus récente. Les autres sont perdues. */
export function legacyLatestOnly(rows, opts) {
  return selectAnnouncements(rows, { ...opts, after: 0 }).latest;
}

/**
 * Une source seule (activation) ou un tableau (trio). L'ancien code
 * appelait `.map` sur l'objet → exception, licence écrite, liste perdue.
 */
export function coerceSourceList(sources) {
  if (Array.isArray(sources)) return sources.filter(Boolean);
  if (sources && typeof sources === 'object') return [sources];
  return [];
}

/**
 * Décide ce que l'app a le droit de recevoir.
 * Une liste effacée (tombstone) ne doit PAS revenir via le repli KV.
 * Une nouvelle ligne D1 (ré-assignation) prime sur le tombstone.
 */
export function resolvePublicSource({ d1Sources, kvSource, clearedAt }) {
  const d1 = Array.isArray(d1Sources) ? d1Sources.filter(Boolean) : [];
  if (d1.length > 0) {
    return { source: d1[0], sources: d1, cleared: false, from: 'd1' };
  }
  if (clearedAt) {
    return { source: null, sources: [], cleared: true, from: 'tombstone' };
  }
  if (kvSource && typeof kvSource === 'object') {
    return { source: kvSource, sources: [kvSource], cleared: false, from: 'kv' };
  }
  return { source: null, sources: [], cleared: false, from: 'none' };
}

export async function markSourcesCleared(env, mac, now = Date.now()) {
  if (!env || !env.DB) return;
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS device_source_clears (' +
      'mac TEXT PRIMARY KEY, cleared_at INTEGER NOT NULL)',
  ).run();
  await env.DB.prepare(
    'INSERT INTO device_source_clears (mac, cleared_at) VALUES (?, ?) ' +
      'ON CONFLICT(mac) DO UPDATE SET cleared_at = excluded.cleared_at',
  ).bind(mac, now).run();
  await scrubKvPlaylists(env, mac);
}

export async function clearSourceTombstone(env, mac) {
  if (!env || !env.DB) return;
  try {
    await env.DB.prepare('DELETE FROM device_source_clears WHERE mac = ?')
      .bind(mac).run();
  } catch (_) { /* table pas encore créée : rien à effacer */ }
}

export async function readSourceTombstone(env, mac) {
  if (!env || !env.DB) return 0;
  try {
    const row = await env.DB.prepare(
      'SELECT cleared_at FROM device_source_clears WHERE mac = ?',
    ).bind(mac).first();
    return row && row.cleared_at ? Number(row.cleared_at) : 0;
  } catch (_) {
    return 0;
  }
}

/// Vide les playlists KV de cette MAC sans toucher au reste de la fiche.
/// Ne journalise jamais le contenu (identifiants possibles).
export async function scrubKvPlaylists(env, mac) {
  const kv = env && env.KV_7MOTION;
  if (!kv || typeof kv.get !== 'function' || typeof kv.put !== 'function') return;
  try {
    const raw = await kv.get('client:' + mac);
    if (!raw) return;
    const data = JSON.parse(raw);
    if (!data || !Array.isArray(data.playlists) || data.playlists.length === 0) return;
    data.playlists = [];
    data.updated_at = Date.now();
    await kv.put('client:' + mac, JSON.stringify(data));
  } catch (_) { /* KV absent : le tombstone D1 suffit */ }
}
