// =========================================================
//  source_revoke.js — Retrait d'UNE liste, prouvé à la box
// =========================================================
//  Le panel (compte authentifié) retire une source. On écrit une
//  TOMBSTONE : l'empreinte de cette liste, sans mot de passe.
//  La box lit ces empreintes (GET /api/status et /api/device-source)
//  et efface chez elle la liste qui correspond. Une box ne peut
//  pas écrire ici : il n'y a aucune route publique d'effacement.
//
//  Empreinte (identique côté Dart, source_fingerprint.dart) :
//    xtream|<serveur sans slash final, en minuscules>|<identifiant>
//    m3u|<url exacte, espaces retirés>
// =========================================================

import { encryptionKey, openSource, sealSource } from './source_crypto.js';

export function sourceFingerprint(item) {
  if (!item || typeof item !== 'object') return null;
  const type = String(item.type || '').trim().toLowerCase();
  if (type === 'xtream') {
    const server = String(item.server_url || '').trim().replace(/\/+$/, '').toLowerCase();
    const user = String(item.username || '').trim();
    if (!server || !user) return null;
    return `xtream|${server}|${user}`;
  }
  if (type === 'm3u') {
    const url = String(item.m3u_url || '').trim();
    if (!url) return null;
    return `m3u|${url}`;
  }
  return null;
}

/// Forme publique : pas de mot de passe, pas d'URL secrète en clair
/// au-delà de ce que la box a DÉJÀ en local pour reconnaître sa liste.
export function fingerprintToPublic(fp) {
  const text = String(fp || '');
  if (text.startsWith('xtream|')) {
    const parts = text.split('|');
    if (parts.length < 3) return null;
    return { type: 'xtream', server_url: parts[1], username: parts.slice(2).join('|') };
  }
  if (text.startsWith('m3u|')) {
    const url = text.slice(4);
    if (!url) return null;
    return { type: 'm3u', m3u_url: url };
  }
  return null;
}

export async function ensureRevocationTable(env) {
  if (!env || !env.DB) return;
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS source_revocations (
       mac TEXT NOT NULL,
       fingerprint TEXT NOT NULL,
       created_at INTEGER NOT NULL,
       PRIMARY KEY (mac, fingerprint)
     )`,
  ).run();
}

export async function revokeFingerprints(env, mac, fingerprints) {
  if (!env || !env.DB) return;
  await ensureRevocationTable(env);
  const now = Date.now();
  for (const fp of fingerprints || []) {
    if (!fp) continue;
    await env.DB.prepare(
      `INSERT INTO source_revocations (mac, fingerprint, created_at)
       VALUES (?, ?, ?)
       ON CONFLICT(mac, fingerprint) DO UPDATE SET created_at = excluded.created_at`,
    ).bind(mac, fp, now).run();
  }
}

/// Une liste ré-assignée ne doit plus être une tombstone, sinon la
/// box l'effacerait juste après l'avoir reçue.
export async function clearRevocations(env, mac, fingerprints) {
  if (!env || !env.DB) return;
  await ensureRevocationTable(env);
  for (const fp of fingerprints || []) {
    if (!fp) continue;
    await env.DB.prepare(
      'DELETE FROM source_revocations WHERE mac = ? AND fingerprint = ?',
    ).bind(mac, fp).run();
  }
}

export async function listRevokedPublic(env, mac) {
  if (!env || !env.DB) return [];
  try {
    await ensureRevocationTable(env);
    const rs = await env.DB.prepare(
      'SELECT fingerprint FROM source_revocations WHERE mac = ?',
    ).bind(mac).all();
    return (rs.results || [])
      .map((r) => fingerprintToPublic(r.fingerprint))
      .filter(Boolean);
  } catch (_) {
    return [];
  }
}

/// Numéro que la box compare. Change quand on pose, retire ou
/// réécrit les sources. 0 = rien. `undefined` = base illisible
/// (l'app retombe sur l'ancien rythme).
export async function sourceRevForMac(env, mac) {
  if (!env || !env.DB) return undefined;
  let updated = 0;
  let revokedAt = 0;
  try {
    const row = await env.DB.prepare(
      'SELECT updated_at FROM device_sources WHERE mac = ?',
    ).bind(mac).first();
    if (row && row.updated_at) updated = Number(row.updated_at) || 0;
  } catch (_) {
    return undefined;
  }
  try {
    await ensureRevocationTable(env);
    const row = await env.DB.prepare(
      'SELECT MAX(created_at) AS t FROM source_revocations WHERE mac = ?',
    ).bind(mac).first();
    if (row && row.t) revokedAt = Number(row.t) || 0;
  } catch (_) { /* table absente : le updated_at suffit */ }
  return Math.max(updated, revokedAt);
}

export async function readOpenedSources(env, mac) {
  if (!env || !env.DB) return [];
  let row;
  try {
    row = await env.DB.prepare(
      `SELECT type, label, server_url, username, password, m3u_url, epg_url,
              sources_json, origin
         FROM device_sources WHERE mac = ?`,
    ).bind(mac).first();
  } catch (_) {
    return [];
  }
  if (!row) return [];
  let items = [];
  if (row.sources_json) {
    try { items = JSON.parse(row.sources_json) || []; } catch (_) { items = []; }
  }
  if (!items.length) {
    items = [{
      type: row.type, label: row.label, server_url: row.server_url,
      username: row.username, password: row.password, m3u_url: row.m3u_url,
      epg_url: row.epg_url, origin: row.origin || 'panel',
    }];
  }
  const key = encryptionKey(env);
  const out = [];
  for (const it of items) out.push(await openSource(it, key));
  return out;
}

/// Remplace la ligne. Liste vide = plus de source, mais les
/// tombstones restent (la box hors-ligne les lira au retour).
export async function writeOpenedSources(env, mac, items) {
  if (!env || !env.DB) return;
  if (!items || !items.length) {
    try {
      await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(mac).run();
    } catch (_) { /* déjà vide */ }
    return;
  }
  const key = encryptionKey(env);
  const sealed = [];
  for (const it of items) sealed.push(await sealSource(it, key));
  const first = sealed[0];
  const rowOrigin = sealed.every((s) => s.origin === 'self') ? 'self' : 'panel';
  const jsonStr = JSON.stringify(sealed);
  await env.DB.prepare(
    `INSERT INTO device_sources
       (mac, type, label, server_url, username, password, m3u_url, epg_url,
        sources_json, origin, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(mac) DO UPDATE SET
       type=excluded.type, label=excluded.label, server_url=excluded.server_url,
       username=excluded.username, password=excluded.password,
       m3u_url=excluded.m3u_url, epg_url=excluded.epg_url,
       sources_json=excluded.sources_json, origin=excluded.origin,
       updated_at=excluded.updated_at`,
  ).bind(
    mac, first.type || 'm3u', first.label || null, first.server_url || null,
    first.username || null, first.password || null, first.m3u_url || null,
    first.epg_url || null, jsonStr, rowOrigin, Date.now(),
  ).run();
}

/// Empreintes présentes avant et plus après. On ne révoque pas une
/// liste encore dans [nextItems].
export function droppedFingerprints(previousItems, nextItems) {
  const next = new Set((nextItems || []).map(sourceFingerprint).filter(Boolean));
  const gone = [];
  for (const item of previousItems || []) {
    const fp = sourceFingerprint(item);
    if (fp && !next.has(fp) && !gone.includes(fp)) gone.push(fp);
  }
  return gone;
}
