// =========================================================
//  blackbox_journal.js — Journal « Boîte noire » par MAC
// =========================================================
//  Même lien que le heartbeat et le statut : la MAC virtuelle,
//  le Worker, la base D1. L'app envoie les dernières lignes
//  (POST /api/blackbox). Le panel les relit (GET /api/v1/blackbox).
//
//  On masque AVANT d'écrire, même si l'app l'a déjà fait : une
//  vieille version, ou un envoi bricolé, ne doit pas poser une
//  adresse de flux, un mot de passe ou un identifiant en base.
//  Les lignes [SON] ne sont pas des secrets.
//
//  Mêmes règles que lib/core/blackbox/black_box_redaction.dart.
// =========================================================

/// 32 Ko : assez pour les dernières lignes de l'écran (400),
/// sous la limite d'une requête D1 (~100 Ko).
export const BLACKBOX_MAX_BYTES = 32 * 1024;

const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

export function isBlackboxMac(mac) {
  return typeof mac === 'string' && MAC_RX.test(mac.trim());
}

/// `null` si coupé ou vide. Sinon texte masqué, fin seulement.
export function prepareBlackBoxText(raw, opts = {}) {
  const enabled = opts.enabled !== false;
  if (!enabled) return null;
  if (typeof raw !== 'string') return null;
  const capped = raw.length > 256 * 1024 ? raw.slice(-256 * 1024) : raw;
  const max = opts.maxBytes || BLACKBOX_MAX_BYTES;
  const clean = truncateBlackBoxTail(redactBlackBox(capped), max);
  if (!clean.trim()) return null;
  return clean;
}

export function redactBlackBox(input) {
  let text = String(input ?? '');
  const urlRe = /\b(?:https?|rtsps?|rtmps?|udp|rtp|mms|mmsh):\/\/[^\s<>"'()]+/gi;
  const userInfoRe = /\b[^:\s/@]{1,80}:[^:\s/@]{1,80}@[\w.-]+(?::\d+)?/g;
  const pathRe = /\/(live|movie|series)\/[^/\s]+\/[^/\s]+\//gi;
  const fieldRe = /\b(password|passwd|pwd|username|user|login|token|auth|pass)\b\s*[:=]\s*[^\s&,;]+/gi;
  const labelRe = /\b(utilisateur|identifiant)\b\s*[:=]?\s+\S+/gi;
  const emailRe = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;
  text = text.replace(urlRe, '[lien]');
  text = text.replace(userInfoRe, '[identifiants]');
  text = text.replace(pathRe, (_, kind) => `/${kind}/[masqué]/[masqué]/`);
  text = text.replace(fieldRe, (_, key) => `${key}=[masqué]`);
  text = text.replace(labelRe, (_, word) => `${word} [masqué]`);
  text = text.replace(emailRe, '[identifiant]');
  return text;
}

export function truncateBlackBoxTail(text, maxBytes) {
  if (maxBytes <= 0) return '';
  const enc = new TextEncoder();
  const dec = new TextDecoder('utf-8', { fatal: false });
  const bytes = enc.encode(text);
  if (bytes.length <= maxBytes) return text;
  let slice = bytes.subarray(bytes.length - maxBytes);
  let i = 0;
  while (i < slice.length && (slice[i] & 0xc0) === 0x80) i += 1;
  if (i > 0) slice = slice.subarray(i);
  let s = dec.decode(slice);
  const nl = s.indexOf('\n');
  if (nl >= 0 && nl < s.length - 1) s = s.slice(nl + 1);
  return s;
}

let tableReady = false;

export async function ensureBlackboxTable(env) {
  if (tableReady || !env || !env.DB) return;
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS device_blackbox ('
    + 'mac TEXT PRIMARY KEY, '
    + 'body TEXT NOT NULL, '
    + 'updated_at INTEGER NOT NULL, '
    + 'requested_at INTEGER NOT NULL DEFAULT 0)',
  ).run();
  tableReady = true;
}

/// Écrit le journal déjà filtré. Ne touche pas à `requested_at`
/// (la demande du panel reste en place).
export async function saveBlackBox(env, mac, text, now = Date.now()) {
  if (!env || !env.DB) return { error: 'no_db' };
  const clean = prepareBlackBoxText(text, { enabled: true });
  if (clean == null) return { error: 'empty' };
  await ensureBlackboxTable(env);
  await env.DB.prepare(
    'INSERT INTO device_blackbox (mac, body, updated_at, requested_at) '
    + 'VALUES (?, ?, ?, 0) '
    + 'ON CONFLICT(mac) DO UPDATE SET '
    + 'body = excluded.body, updated_at = excluded.updated_at',
  ).bind(mac, clean, now).run();
  return { updated_at: now };
}

export async function readBlackBox(env, mac) {
  if (!env || !env.DB) return { body: '', updated_at: 0 };
  try {
    await ensureBlackboxTable(env);
    const row = await env.DB.prepare(
      'SELECT body, updated_at FROM device_blackbox WHERE mac = ?',
    ).bind(mac).first();
    if (!row) return { body: '', updated_at: 0 };
    return {
      body: typeof row.body === 'string' ? row.body : '',
      updated_at: Number(row.updated_at) || 0,
    };
  } catch (_) {
    return { body: '', updated_at: 0 };
  }
}

/// Horodatage de la demande panel (0 = personne ne regarde).
/// Le statut public le renvoie : la box l'a déjà dans sa veille.
export async function blackboxRequestedAt(env, mac) {
  if (!env || !env.DB || !mac) return 0;
  try {
    await ensureBlackboxTable(env);
    const row = await env.DB.prepare(
      'SELECT requested_at FROM device_blackbox WHERE mac = ?',
    ).bind(mac).first();
    return row && row.requested_at ? Number(row.requested_at) : 0;
  } catch (_) {
    return 0;
  }
}

/// Le panel veut un journal frais. N'efface pas le texte déjà reçu.
export async function markBlackBoxAsked(env, mac, now = Date.now()) {
  if (!env || !env.DB) return 0;
  await ensureBlackboxTable(env);
  await env.DB.prepare(
    'INSERT INTO device_blackbox (mac, body, updated_at, requested_at) '
    + "VALUES (?, '', 0, ?) "
    + 'ON CONFLICT(mac) DO UPDATE SET requested_at = excluded.requested_at',
  ).bind(mac, now).run();
  return now;
}
