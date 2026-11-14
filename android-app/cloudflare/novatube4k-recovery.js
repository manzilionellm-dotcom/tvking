// Réassociation NOVATUBE après perte de la clé locale. Connaître une MAC
// ne suffit jamais : la nouvelle installation reçoit un code temporaire,
// que le propriétaire remet à un administrateur déjà authentifié.
// Aucun champ de licence, source, client, revendeur ou crédit n'est modifié.
import { readNovatubePanelActor } from './novatube4k-panel-admin.js';

const APP = 'app_novatube4k';
const PACKAGE = 'com.manthefew';
const ADMIN_PATH = '/api/v1/novatube4k/reassociate';
const MAC = /^MK(?::[0-9A-F]{2}){5}$/;
const HEX = /^[a-f0-9]{64}$/;
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const CODE = /^[0-9A-HJKMNP-TV-Z]{12}$/;
const TTL = 10 * 60_000;
const SLOTS = 3;
const ready = new WeakSet();

function sameHash(a, b) {
  if (!HEX.test(a || '') || !HEX.test(b || '')) return false;
  const encoder = new TextEncoder();
  if (typeof crypto.subtle.timingSafeEqual === 'function') {
    return crypto.subtle.timingSafeEqual(encoder.encode(a), encoder.encode(b));
  }
  let difference = 0;
  for (let i = 0; i < 64; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}

function normalizeMac(value) {
  const mac = typeof value === 'string' ? value.trim().toUpperCase() : '';
  return MAC.test(mac) ? mac : null;
}

export function normalizeNovatubeRecoveryCode(value) {
  if (typeof value !== 'string' || value.length > 64) return null;
  const code = value.toUpperCase().replace(/[-\s]/g, '');
  return CODE.test(code) ? code.match(/.{4}/g).join('-') : null;
}

function randomCode() {
  // 12 symboles indépendants de 5 bits : 60 bits issus du CSPRNG Workers.
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return Array.from(bytes, (byte) => ALPHABET[byte & 31]).join('').match(/.{4}/g).join('-');
}

function metadata(value, maximum) {
  if (typeof value !== 'string') return null;
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/https?:\/\/\S+/gi, '[expurgé]')
    .replace(/\b[a-f0-9]{64}\b/gi, '[expurgé]').trim().slice(0, maximum);
  return cleaned || null;
}

async function schema(env) {
  if (ready.has(env.DB)) return;
  // Trois emplacements fixes par liaison : même après des expirations,
  // un appareil ne peut accumuler une liste non bornée de candidats.
  await env.DB.batch([
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_recovery_requests (
      raw_mac TEXT NOT NULL,
      slot INTEGER NOT NULL CHECK (slot >= 0 AND slot < 3),
      request_id TEXT NOT NULL UNIQUE,
      mac TEXT NOT NULL,
      device_id TEXT NOT NULL,
      old_key_hash TEXT NOT NULL,
      new_key_hash TEXT NOT NULL,
      code TEXT NOT NULL UNIQUE,
      state TEXT NOT NULL CHECK (state IN ('pending', 'approved', 'superseded')),
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      model TEXT, app_version TEXT, platform TEXT,
      approved_at INTEGER, approved_by TEXT,
      PRIMARY KEY (raw_mac, slot),
      FOREIGN KEY (raw_mac) REFERENCES novatube4k_devices(raw_mac) ON DELETE CASCADE
    )`),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_recovery_guard (
      id TEXT PRIMARY KEY, valid INTEGER NOT NULL CHECK (valid = 1)
    )`),
  ]);
  ready.add(env.DB);
}

// La portée exige la liaison NOVATUBE, la fiche correspondante, l'application
// exacte et sa licence. Une licence inactive reste inactive après réparation.
// Une fiche d'une autre application n'est jamais adoptée par cette fonction.
async function binding(env, field, value) {
  const column = field === 'raw' ? 'n.raw_mac' : 'n.mac';
  try {
    return await env.DB.prepare(`SELECT n.raw_mac, n.mac, n.device_id, n.device_key_hash
      FROM novatube4k_devices n
      JOIN devices d ON d.id = n.device_id AND d.mac = n.mac
      JOIN apps a ON a.id = ? AND a.package_name = ?
      WHERE ${column} = ? AND EXISTS (
        SELECT 1 FROM licenses l WHERE l.device_id = n.device_id AND l.app_id = a.id
      )`).bind(APP, PACKAGE, value).first();
  } catch (error) {
    if (/no such table:\s*novatube4k_devices\b/i.test(String(error?.message || ''))) return null;
    throw error;
  }
}

async function pendingFor(env, current, newHash, now) {
  return env.DB.prepare(`SELECT request_id, code, expires_at FROM novatube4k_recovery_requests
    WHERE raw_mac = ? AND mac = ? AND device_id = ? AND old_key_hash = ?
      AND new_key_hash = ? AND state = 'pending' AND expires_at > ? LIMIT 1`)
    .bind(current.raw_mac, current.mac, current.device_id, current.device_key_hash, newHash, now).first();
}

function pending(row) {
  return { recovery: { status: 'pending', code: row.code, expires_at: row.expires_at } };
}

/** Seulement appelée après un register avec clé valide de format, différente. */
export async function offerNovatubeRecovery(env, prior, newHash, input = {}) {
  if (!HEX.test(newHash || '')) throw new Error('invalid_recovery_hash');
  await schema(env);
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await binding(env, 'raw', prior.raw_mac);
    if (!current || current.mac !== prior.mac || current.device_id !== prior.device_id) {
      return { error: 'device_registration_missing' };
    }
    // L'approbation peut avoir gagné pendant le register en cours.
    if (sameHash(current.device_key_hash, newHash)) return { binding: current };
    const now = Date.now();
    const existing = await pendingFor(env, current, newHash, now);
    if (existing) return pending(existing);
    const code = randomCode(), requestId = crypto.randomUUID();
    try {
      // Une seule instruction choisit un emplacement libre ET revalide la clé
      // courante. Deux demandes concurrentes ne dépassent pas les trois slots,
      // et deux envois de la même clé retrouvent le même code sans prolonger TTL.
      await env.DB.prepare(`INSERT INTO novatube4k_recovery_requests
        (raw_mac, slot, request_id, mac, device_id, old_key_hash, new_key_hash,
         code, state, created_at, expires_at, model, app_version, platform)
        SELECT ?, slots.slot, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?
        FROM (SELECT 0 AS slot UNION ALL SELECT 1 UNION ALL SELECT 2) slots
        LEFT JOIN novatube4k_recovery_requests r ON r.raw_mac = ? AND r.slot = slots.slot
        WHERE (r.raw_mac IS NULL OR r.state <> 'pending' OR r.expires_at <= ?
          OR r.old_key_hash <> ? OR r.mac <> ? OR r.device_id <> ?)
          AND EXISTS (SELECT 1 FROM novatube4k_devices n WHERE n.raw_mac = ?
            AND n.mac = ? AND n.device_id = ? AND n.device_key_hash = ?)
          AND NOT EXISTS (SELECT 1 FROM novatube4k_recovery_requests same
            WHERE same.raw_mac = ? AND same.old_key_hash = ? AND same.new_key_hash = ?
              AND same.mac = ? AND same.device_id = ? AND same.state = 'pending' AND same.expires_at > ?)
        ORDER BY slots.slot LIMIT 1
        ON CONFLICT(raw_mac, slot) DO UPDATE SET
          request_id = excluded.request_id, mac = excluded.mac, device_id = excluded.device_id,
          old_key_hash = excluded.old_key_hash, new_key_hash = excluded.new_key_hash,
          code = excluded.code, state = excluded.state, created_at = excluded.created_at,
          expires_at = excluded.expires_at, model = excluded.model, app_version = excluded.app_version,
          platform = excluded.platform, approved_at = NULL, approved_by = NULL`)
        .bind(current.raw_mac, requestId, current.mac, current.device_id, current.device_key_hash,
          newHash, code, now, now + TTL, metadata(input.model, 96), metadata(input.appVersion, 40),
          metadata(input.platform, 24), current.raw_mac, now, current.device_key_hash,
          current.mac, current.device_id, current.raw_mac, current.mac, current.device_id,
          current.device_key_hash, current.raw_mac, current.device_key_hash, newHash,
          current.mac, current.device_id, now).run();
    } catch (error) {
      // Une collision aléatoire de code ne doit jamais lier deux appareils.
      if (/UNIQUE constraint failed:\s*novatube4k_recovery_requests\.code/i.test(String(error?.message || ''))) continue;
      throw error;
    }
    const issued = await pendingFor(env, current, newHash, Date.now());
    if (issued) return pending(issued);
    const active = await binding(env, 'raw', prior.raw_mac);
    if (!active || active.mac !== prior.mac || active.device_id !== prior.device_id) return { error: 'device_registration_missing' };
    if (!sameHash(active.device_key_hash, current.device_key_hash)) continue;
    const quota = await env.DB.prepare(`SELECT COUNT(*) AS count, MIN(expires_at) AS next_expiry
      FROM novatube4k_recovery_requests WHERE raw_mac = ? AND old_key_hash = ?
        AND mac = ? AND device_id = ? AND state = 'pending' AND expires_at > ?`)
      .bind(current.raw_mac, current.device_key_hash, current.mac, current.device_id, Date.now()).first();
    if (Number(quota?.count) >= SLOTS) {
      return { recovery: { status: 'unavailable', retry_after: Math.max(1, Math.min(600,
        Math.ceil((Number(quota.next_expiry) - Date.now()) / 1000))) } };
    }
  }
  return { recovery: { status: 'unavailable', retry_after: 5 } };
}

const MESSAGES = {
  invalid_recovery_request: 'Saisis la MAC Atlas et le code affiché sur la box.',
  recovery_not_supported: 'Cette fiche ne permet pas une réassociation NOVATUBE.',
  recovery_not_found: 'Ce code ne correspond pas à cette fiche. Vérifie le code affiché sur la box.',
  recovery_expired: 'Ce code a expiré. Utilise le nouveau code affiché sur la box.',
  recovery_consumed: 'Cette demande a déjà été traitée. Relis l’état de la box.',
  recovery_stale: 'La liaison a changé. Relis le nouveau code de la box avant de confirmer.',
  recovery_unavailable: 'La réassociation est momentanément indisponible.',
  rate_limited: 'Trop de tentatives. Réessaie dans une minute.',
  forbidden: 'Réservé à l’administrateur.',
  method_not_allowed: 'Méthode non autorisée.',
  body_too_large: 'La demande est trop volumineuse.',
};
function reply(headers, body, status = 200) { return Response.json(body, { status, headers }); }
function failure(headers, error, status = 409) {
  return reply(headers, { ok: false, error, message: MESSAGES[error] }, status);
}

async function readInput(request) {
  const reader = request.body?.getReader();
  if (!reader) return { input: null };
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 4096) { await reader.cancel(); return { oversized: true }; }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return { input: JSON.parse(new TextDecoder().decode(bytes)) };
  } catch { return { input: null }; }
  finally { reader.releaseLock(); }
}

async function candidateFor(env, mac, code) {
  try {
    return await env.DB.prepare('SELECT * FROM novatube4k_recovery_requests WHERE mac = ? AND code = ?')
      .bind(mac, code).first();
  } catch (error) {
    if (/no such table:\s*novatube4k_recovery_requests\b/i.test(String(error?.message || ''))) return null;
    throw error;
  }
}

function candidateError(row, current, now, expectedId) {
  if (!row) return 'recovery_not_found';
  if (expectedId && row.request_id !== expectedId) return 'recovery_stale';
  if (row.state !== 'pending') return 'recovery_consumed';
  if (row.expires_at <= now) return 'recovery_expired';
  if (row.raw_mac !== current.raw_mac || row.device_id !== current.device_id || row.mac !== current.mac
    || !sameHash(row.old_key_hash, current.device_key_hash)) return 'recovery_stale';
  return null;
}

// Une licence active ne prouve pas que l'installation visible sur la TV
// possède la clé actuellement liée. Le panneau propriétaire peut signaler
// ce blocage sans connaître ni énumérer les codes à saisir physiquement.
// Cette lecture n'initialise aucune table, ne prolonge aucune demande et
// n'approuve rien. « unknown » ne promet donc jamais une livraison à la TV.
async function installationState(env, current, now) {
  let expiresAt = null;
  try {
    const row = await env.DB.prepare(`SELECT MAX(r.expires_at) AS expires_at
      FROM novatube4k_recovery_requests r
      JOIN novatube4k_devices n ON n.raw_mac = r.raw_mac AND n.mac = r.mac
        AND n.device_id = r.device_id AND n.device_key_hash = r.old_key_hash
      WHERE r.raw_mac = ? AND r.mac = ? AND r.device_id = ?
        AND r.state = 'pending' AND r.new_key_hash <> n.device_key_hash
        AND r.created_at <= ? AND r.expires_at > ? AND r.expires_at <= ?`)
      .bind(current.raw_mac, current.mac, current.device_id, now, now, now + TTL).first();
    if (Number.isSafeInteger(row?.expires_at) && row.expires_at > now) expiresAt = row.expires_at;
  } catch (error) {
    // Une installation sans conflit n'a encore jamais créé cette table.
    // Les autres pannes restent un échec explicite, jamais un faux feu vert.
    if (!/no such table:\s*novatube4k_recovery_requests\b/i.test(String(error?.message || ''))) throw error;
  }
  return { installation_status: expiresAt === null ? 'unknown' : 'verification_required',
    recovery_pending: expiresAt !== null, server_now: now, recovery_expires_at: expiresAt };
}

/** Les routes admin n'énumèrent jamais les demandes ni leurs codes. */
export async function handleNovatubeRecoveryAdmin(request, env, ctx, original, deps) {
  const url = new URL(request.url);
  const path = '/' + url.pathname.split('/').filter(Boolean).join('/');
  if (![ADMIN_PATH, ADMIN_PATH + '/preview', ADMIN_PATH + '/approve'].includes(path)
    || request.method === 'OPTIONS') return null;
  const gate = await readNovatubePanelActor(request, env, ctx, original);
  if (gate.error) return gate.error;
  const { user, headers } = gate;
  headers.set('Cache-Control', 'no-store, private');
  headers.set('X-Content-Type-Options', 'nosniff');
  if (user?.role !== 'super_admin') return failure(headers, 'forbidden', 403);
  if ((path === ADMIN_PATH && request.method !== 'GET')
      || (path !== ADMIN_PATH && request.method !== 'POST')) return failure(headers, 'method_not_allowed', 405);
  if (!env?.DB || typeof deps.rateLimitOk !== 'function') return failure(headers, 'recovery_unavailable', 503);
  try {
    if (!await deps.rateLimitOk(env, request, 'novatube4k-reassociate', 30, 60_000)) return failure(headers, 'rate_limited', 429);
    let mac, code, expectedId;
    if (path === ADMIN_PATH) {
      mac = normalizeMac(url.searchParams.get('mac'));
    } else {
      const parsed = await readInput(request);
      if (parsed.oversized) return failure(headers, 'body_too_large', 413);
      const input = parsed.input;
      if (!input || typeof input !== 'object' || Array.isArray(input)) return failure(headers, 'invalid_recovery_request', 400);
      mac = normalizeMac(input.mac); code = normalizeNovatubeRecoveryCode(input.code);
      if (path.endsWith('/approve') && input.request_id === undefined) {
        return failure(headers, 'invalid_recovery_request', 400);
      }
      if (input.request_id !== undefined) {
        if (typeof input.request_id !== 'string'
          || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(input.request_id)) {
          return failure(headers, 'invalid_recovery_request', 400);
        }
        expectedId = input.request_id;
      }
      if (!code) return failure(headers, 'invalid_recovery_request', 400);
    }
    if (!mac) return failure(headers, 'invalid_recovery_request', 400);
    const current = await binding(env, 'mac', mac);
    if (!current) return failure(headers, 'recovery_not_supported', 404);
    if (path === ADMIN_PATH) return reply(headers, { ok: true, supported: true, app_id: APP, mac,
      ...await installationState(env, current, Date.now()) });
    const row = await candidateFor(env, mac, code);
    const now = Date.now();
    const invalid = candidateError(row, current, now, expectedId);
    if (invalid) return failure(headers, invalid);
    if (path.endsWith('/preview')) {
      return reply(headers, { ok: true, app_id: APP, mac, server_now: now, candidate: {
        request_id: row.request_id, created_at: row.created_at, expires_at: row.expires_at,
        model: row.model, app_version: row.app_version, platform: row.platform,
      } });
    }
    const guardId = crypto.randomUUID();
    // Le CHECK est relu DANS le lot atomique. Une approbation concurrente,
    // un transfert ou une suppression rend tout le lot caduc, audit compris.
    const statements = [
      env.DB.prepare(`INSERT INTO novatube4k_recovery_guard (id, valid)
        SELECT ?, CASE WHEN EXISTS (
          SELECT 1 FROM novatube4k_recovery_requests r
          JOIN novatube4k_devices n ON n.raw_mac = r.raw_mac AND n.mac = r.mac
            AND n.device_id = r.device_id AND n.device_key_hash = r.old_key_hash
          JOIN devices d ON d.id = n.device_id AND d.mac = n.mac
          JOIN apps a ON a.id = ? AND a.package_name = ?
          WHERE r.request_id = ? AND r.raw_mac = ? AND r.mac = ? AND r.device_id = ?
            AND r.old_key_hash = ? AND r.new_key_hash = ? AND r.code = ?
            AND r.state = 'pending' AND r.expires_at > ?
            AND r.expires_at > CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
            AND EXISTS (SELECT 1 FROM licenses l WHERE l.device_id = n.device_id AND l.app_id = a.id)
        ) THEN 1 ELSE 0 END`).bind(guardId, APP, PACKAGE, row.request_id, row.raw_mac,
        row.mac, row.device_id, row.old_key_hash, row.new_key_hash, row.code, now),
      env.DB.prepare(`UPDATE novatube4k_devices SET device_key_hash = ?, updated_at = ?, last_served_rev = NULL
        WHERE raw_mac = ? AND mac = ? AND device_id = ? AND device_key_hash = ?`)
        .bind(row.new_key_hash, now, row.raw_mac, row.mac, row.device_id, row.old_key_hash),
      env.DB.prepare(`UPDATE novatube4k_recovery_requests SET state = 'approved', approved_at = ?, approved_by = ?
        WHERE request_id = ? AND state = 'pending'`).bind(now, user.sub, row.request_id),
      env.DB.prepare(`UPDATE novatube4k_recovery_requests SET state = 'superseded'
        WHERE raw_mac = ? AND request_id <> ? AND state = 'pending'`).bind(row.raw_mac, row.request_id),
      env.DB.prepare(`INSERT INTO audit_logs
        (id, actor_type, actor_id, action, target_type, target_id, before_json, after_json,
         ip, user_agent, created_at) VALUES (?, 'admin', ?, 'device.key_reassociate', 'device', ?, ?, ?, ?, ?, ?)`)
        .bind('aud_' + crypto.randomUUID(), user.sub, row.device_id,
          JSON.stringify({ app_id: APP, mac: row.mac }),
          JSON.stringify({ app_id: APP, mac: row.mac, request_id: row.request_id, result: 'device_reassociated' }),
          request.headers.get('CF-Connecting-IP'), request.headers.get('User-Agent'), now),
      env.DB.prepare('DELETE FROM novatube4k_recovery_guard WHERE id = ?').bind(guardId),
    ];
    try { await env.DB.batch(statements); }
    catch (error) {
      if (/CHECK constraint failed/i.test(String(error?.message || ''))) return failure(headers, 'recovery_stale');
      return failure(headers, 'recovery_unavailable', 503);
    }
    return reply(headers, { ok: true, app_id: APP, mac, result: 'device_reassociated', approved_at: now });
  } catch {
    // Ni corps de requête, code, clé, empreinte ou erreur SQL dans la réponse.
    return failure(headers, 'recovery_unavailable', 503);
  }
}
