// =========================================================
//  NOVATUBE 4K — liaison explicite appareil / licence Atlas
// =========================================================
//  L'enrôlement crée une fiche visible dans le panel, jamais un essai ni
//  une activation. L'accès dépend uniquement de la licence de cette app.
//  La MAC d'origine reste un alias ; Atlas conserve son format MK habituel.
//  La clé aléatoire de l'installation est envoyée sous HTTPS et seul son
//  SHA-256 est conservé en D1. Une autre clé ne peut pas réclamer la fiche.

import {
  PANEL_BODY_LIMITS, handleNovatube4kPanel, readNovatubePanelSignals,
} from './novatube4k-panel.js';

export const NOVATUBE4K_APP_ID = 'app_novatube4k';
export const NOVATUBE4K_PACKAGE = 'com.manthefew';
const PREFIX = '/api/novatube4k/';
const MAC_RE = /^MK(?::[0-9A-F]{2}){5}$/;
const BODY_LIMIT = 4096;
const schemaReady = new WeakSet();
const encoder = new TextEncoder();

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store, private',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function error(code, status) {
  // Aucun message D1, mot de passe ou clé appareil dans la réponse.
  return json({ ok: false, error: code }, status);
}

export function normalizeNovatube4kRawMac(value) {
  if (typeof value !== 'string' || value.length > 32) return null;
  const raw = value.trim().toUpperCase().replace(/[:.\s-]/g, '');
  return /^[0-9A-F]{12}$/.test(raw) ? raw : null;
}

async function sha256(text) {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(text)));
  return Array.from(bytes, (n) => n.toString(16).padStart(2, '0')).join('');
}

function sameHash(a, b) {
  if (!/^[a-f0-9]{64}$/.test(a || '') || !/^[a-f0-9]{64}$/.test(b || '')) return false;
  if (typeof crypto.subtle.timingSafeEqual === 'function') {
    return crypto.subtle.timingSafeEqual(encoder.encode(a), encoder.encode(b));
  }
  // Node n'expose pas l'extension Workers ; les deux empreintes ont ici
  // toujours la même longueur. Aucun secret brut n'est comparé.
  let difference = 0;
  for (let i = 0; i < 64; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}

export async function novatube4kAtlasMac(rawMac) {
  const raw = normalizeNovatube4kRawMac(rawMac);
  if (!raw) return null;
  const hash = await sha256('novatube4k:' + raw);
  return 'MK:' + hash.slice(0, 10).toUpperCase().match(/../g).join(':');
}

async function ensureSchema(env) {
  if (schemaReady.has(env.DB)) return;
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_devices (
    raw_mac TEXT PRIMARY KEY,
    mac TEXT NOT NULL UNIQUE,
    device_id TEXT NOT NULL UNIQUE,
    device_key_hash TEXT NOT NULL,
    last_served_rev INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
  )`).run();
  const columns = await env.DB.prepare('PRAGMA table_info(novatube4k_devices)').all();
  if (!(columns.results || []).some((column) => column.name === 'last_served_rev')) {
    try {
      await env.DB.prepare('ALTER TABLE novatube4k_devices ADD COLUMN last_served_rev INTEGER').run();
    } catch (e) {
      // Deux isolates peuvent appliquer la même migration au même instant.
      if (!/duplicate column name:\s*last_served_rev\b/i.test(String(e?.message || ''))) throw e;
    }
  }
  schemaReady.add(env.DB);
}

async function bindingForRaw(env, raw) {
  return env.DB.prepare(
    'SELECT raw_mac, mac, device_id, device_key_hash, last_served_rev FROM novatube4k_devices WHERE raw_mac = ?',
  ).bind(raw).first();
}

// Lecture seule pour le wrapper /api/v1/activate. En cas d'erreur D1 autre
// qu'une table absente (avant la première installation), laisser l'appelant
// refuser l'opération ; ne jamais la rediriger vers une autre application.
export async function isNovatube4kMac(env, value) {
  const mac = typeof value === 'string' ? value.trim().toUpperCase() : '';
  if (!MAC_RE.test(mac) || !env?.DB) return false;
  try {
    return !!await env.DB.prepare('SELECT 1 AS found FROM novatube4k_devices WHERE mac = ?').bind(mac).first();
  } catch (e) {
    if (/no such table:\s*novatube4k_devices\b/i.test(String(e?.message || ''))) return false;
    throw e;
  }
}

async function register(env, raw, keyHash) {
  const prior = await bindingForRaw(env, raw);
  if (prior) {
    return sameHash(prior.device_key_hash, keyHash)
      ? { binding: prior, created: false }
      : { response: error('device_key_conflict', 409) };
  }
  const mac = await novatube4kAtlasMac(raw);
  // Même une fiche préparée manuellement ne doit pas être réclamée par une
  // nouvelle clé : l'activation doit suivre le premier enrôlement de l'app.
  const collision = await env.DB.prepare('SELECT id FROM devices WHERE mac = ?').bind(mac).first();
  if (collision) {
    // Une requête jumelle peut avoir terminé entre les deux lectures.
    const winner = await bindingForRaw(env, raw);
    if (winner) return sameHash(winner.device_key_hash, keyHash)
      ? { binding: winner, created: false }
      : { response: error('device_key_conflict', 409) };
    return { response: error('device_identity_conflict', 409) };
  }

  const configured = await env.DB.prepare('SELECT id, package_name FROM apps WHERE id = ? OR package_name = ?')
    .bind(NOVATUBE4K_APP_ID, NOVATUBE4K_PACKAGE).all();
  if ((configured.results || []).some((a) => a.id !== NOVATUBE4K_APP_ID || a.package_name !== NOVATUBE4K_PACKAGE)) {
    return { response: error('app_registration_conflict', 503) };
  }

  const now = Date.now();
  const customerId = 'cus_' + crypto.randomUUID().replace(/-/g, '').slice(0, 24);
  const deviceId = 'dev_' + crypto.randomUUID().replace(/-/g, '').slice(0, 24);
  const licenseId = 'lic_' + crypto.randomUUID().replace(/-/g, '').slice(0, 24);
  const label = 'NOVATUBE 4K · ' + raw;
  try {
    // Le lot D1 est transactionnel : une course ou un conflit annule aussi
    // le client et la licence, sans créer de fiche orpheline.
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO apps
        (id, name, package_name, default_playlist_type, is_active, created_at, updated_at)
        VALUES (?, 'NOVATUBE 4K', ?, 'none', 1, ?, ?)
        ON CONFLICT(id) DO NOTHING`).bind(NOVATUBE4K_APP_ID, NOVATUBE4K_PACKAGE, now, now),
      env.DB.prepare('INSERT INTO customers (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)')
        .bind(customerId, label, now, now),
      env.DB.prepare(`INSERT INTO devices
        (id, customer_id, mac, label, first_seen_at, last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?)`).bind(deviceId, customerId, mac, label, now, now),
      env.DB.prepare(`INSERT INTO licenses
        (id, customer_id, device_id, app_id, status, plan, started_at,
         expires_at, auto_renew, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'inactive', 'custom', ?, 0, 0, ?, ?)`)
        .bind(licenseId, customerId, deviceId, NOVATUBE4K_APP_ID, now, now, now),
      env.DB.prepare(`INSERT INTO novatube4k_devices
        (raw_mac, mac, device_id, device_key_hash, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)`).bind(raw, mac, deviceId, keyHash, now, now),
    ]);
  } catch (e) {
    // Le gagnant d'un double envoi peut déjà avoir engagé le lot. Un rejeu
    // avec la même clé retrouve sa fiche ; une autre clé reste refusée.
    const winner = await bindingForRaw(env, raw);
    if (winner) {
      return sameHash(winner.device_key_hash, keyHash)
        ? { binding: winner, created: false }
        : { response: error('device_key_conflict', 409) };
    }
    const conflict = await env.DB.prepare('SELECT id FROM devices WHERE mac = ?').bind(mac).first();
    if (conflict) return { response: error('device_identity_conflict', 409) };
    throw e;
  }
  return { binding: { raw_mac: raw, mac, device_id: deviceId }, created: true };
}

async function accessFor(env, binding, now) {
  const row = await env.DB.prepare(`SELECT
      d.block_status, a.is_active AS app_active,
      l.status AS license_status, l.plan, l.expires_at
    FROM devices d
    JOIN apps a ON a.id = ?
    LEFT JOIN licenses l ON l.device_id = d.id AND l.app_id = a.id
    WHERE d.id = ? AND d.mac = ?`)
    .bind(NOVATUBE4K_APP_ID, binding.device_id, binding.mac).first();
  if (!row) return null;

  let status = 'inactive';
  if (row.block_status === 'banned' || row.license_status === 'banned') status = 'banned';
  else if (row.block_status === 'frozen' || row.license_status === 'frozen') status = 'frozen';
  else if (row.app_active !== 1) status = 'disabled';
  else if (row.license_status === 'active') {
    const expiry = row.expires_at === null ? null : Number(row.expires_at);
    status = expiry === null || (Number.isFinite(expiry) && expiry > now) ? 'active' : 'expired';
  } else if (row.license_status === 'expired') status = 'expired';

  return { row, status };
}

async function latestRevision(env, mac) {
  try {
    const row = await env.DB.prepare('SELECT MAX(rev) AS rev FROM source_revisions WHERE mac = ?').bind(mac).first();
    const rev = Number(row?.rev);
    return Number.isSafeInteger(rev) && rev > 0 ? rev : null;
  } catch (e) {
    if (/no such table:\s*source_revisions\b/i.test(String(e?.message || ''))) return null;
    throw e;
  }
}

async function sourcesWithIds(sources) {
  const validId = (value) => typeof value === 'string' && /^[A-Za-z0-9._:-]{1,128}$/.test(value);
  const counts = new Map();
  for (const source of sources) {
    if (validId(source?.id)) counts.set(source.id, (counts.get(source.id) || 0) + 1);
  }
  const used = new Set();
  const result = [];
  for (const source of sources) {
    if (!source || typeof source !== 'object' || Array.isArray(source)) throw new Error('invalid_source');
    let id = validId(source.id) && counts.get(source.id) === 1 ? source.id : null;
    if (id === null) {
      const type = String(source.type || '').toLowerCase();
      let address;
      let username = '';
      if (type === 'xtream') {
        const url = new URL(String(source.server_url || '').trim());
        if (!['http:', 'https:'].includes(url.protocol)) throw new Error('invalid_source');
        // Seule l'identité est normalisée. L'adresse réellement fournie au
        // lecteur reste intacte, notamment son préfixe de chemin.
        url.hash = '';
        url.username = '';
        url.password = '';
        url.pathname = url.pathname.replace(/\/+$/, '') || '/';
        address = url.toString();
        if (url.pathname === '/' && !url.search) address = address.replace(/\/$/, '');
        username = String(source.username || '').trim();
      } else if (type === 'm3u') {
        // Une URL M3U peut contenir une signature : la query fait partie de
        // son identité et n'est ni supprimée ni réordonnée.
        address = String(source.m3u_url || '').trim();
        if (!address) throw new Error('invalid_source');
      } else {
        throw new Error('invalid_source');
      }
      id = 'n4k_' + await sha256(type + '\n' + address + '\n' + username);
    }
    // Deux entrées impossibles à distinguer ne doivent pas partager leurs
    // favoris ou écraser un profil local. L'app conservera l'ancien lot.
    if (used.has(id)) throw new Error('ambiguous_source_identity');
    used.add(id);
    result.push({ ...source, id });
  }
  return result;
}

async function touchPresence(env, binding, request, recordPresence, now, created) {
  if (typeof recordPresence !== 'function') return;
  try {
    // updated_at réserve le créneau entre polls concurrents. Cette écriture
    // appartient seulement à notre liaison ; aucun essai n'est prolongé.
    const reserved = await env.DB.prepare(`UPDATE novatube4k_devices SET updated_at = ?
      WHERE raw_mac = ? AND (? = 1 OR updated_at <= ?)`)
      .bind(now, binding.raw_mac, created ? 1 : 0, now - 30_000).run();
    if (reserved?.meta?.changes !== 1) return;
    await recordPresence(env, binding.mac,
      (request.headers.get('CF-Connecting-IP') || '').slice(0, 64),
      (request.headers.get('CF-IPCountry') || '').slice(0, 8), now, '');
  } catch (_) {
    // La présence est un indicateur du panel, jamais une preuve de licence.
  }
}

async function state(env, binding, deps, created, request) {
  const now = Date.now();
  const access = await accessFor(env, binding, now);
  if (!access) return error('device_registration_missing', 409);
  const { row, status } = access;
  await touchPresence(env, binding, request, deps.recordPresence, now, created);
  await env.DB.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ? AND last_seen_at < ?')
    .bind(now, binding.device_id, now - 60_000).run();

  const body = {
    ok: true,
    app_id: NOVATUBE4K_APP_ID,
    mac: binding.mac,
    raw_mac: binding.raw_mac,
    registered: true,
    created: !!created,
    active: status === 'active',
    status,
    plan: row.plan || null,
    expires_at: row.expires_at == null ? null : Number(row.expires_at),
    server_now: now,
    sources: [],
    sources_ok: false,
    source_rev: null,
  };
  // Compatibilité 334.2.1 : champs additifs, sans changer la preuve de licence.
  // Une demande de journal et un reset doivent être vus aussi sur l'écran bloqué.
  if (typeof deps.resetAtFor === 'function' && typeof deps.blackboxRequestedAt === 'function') {
    Object.assign(body, await readNovatubePanelSignals(env, binding, deps));
  }
  if (body.active && typeof deps.readSources === 'function') {
    try {
      // Le handler existant fait le déchiffrement des sources Atlas ;
      // l'appel n'est possible qu'après auth appareil ET licence valable.
      const before = await latestRevision(env, binding.mac);
      const response = await deps.readSources(binding.mac);
      if (response?.ok) {
        const payload = await response.json();
        const after = await latestRevision(env, binding.mac);
        const advertised = payload?.rev == null ? null : Number(payload.rev);
        // Une publication pendant la lecture pourrait associer des sources
        // anciennes au nouveau numéro. Ce cas sera relu au prochain poll.
        if (before === after && advertised === after && payload && !payload.blocked && Array.isArray(payload.sources)) {
          const identified = await sourcesWithIds(payload.sources);
          if (after !== null) {
            await env.DB.prepare(`UPDATE novatube4k_devices SET last_served_rev = ?
              WHERE raw_mac = ? AND (last_served_rev IS NULL OR last_served_rev <= ?)`)
              .bind(after, binding.raw_mac, after).run();
          }
          body.sources = identified;
          body.sources_ok = true;
          body.source_rev = after;
        }
      }
    } catch (_) {
      // Une panne de catalogue ne vaut pas suppression des listes locales.
      // sources_ok=false distingue ce cas d'une vraie liste Atlas vide.
    }
  }
  return json(body);
}

async function acknowledge(env, binding, input, deps) {
  const rev = input.source_rev;
  if (input.applied !== true || !Number.isSafeInteger(rev) || rev <= 0) return error('invalid_ack', 400);
  const now = Date.now();
  const access = await accessFor(env, binding, now);
  if (!access) return error('device_registration_missing', 409);
  if (access.status !== 'active') return error('license_inactive', 403);
  if (Number(binding.last_served_rev) !== rev || await latestRevision(env, binding.mac) !== rev) {
    return error('source_revision_conflict', 409);
  }
  if (typeof deps.recordAck !== 'function' || typeof deps.markRevisionAck !== 'function') {
    return error('ack_unavailable', 503);
  }
  const published = await env.DB.prepare('SELECT state FROM source_revisions WHERE mac = ? AND rev = ?')
    .bind(binding.mac, rev).first();
  if (!published || !['published', 'acknowledged'].includes(published.state)) return error('source_revision_conflict', 409);
  const orders = await env.DB.prepare(`SELECT order_id FROM box_orders
    WHERE mac = ? AND config_rev = ? AND kind IN ('source', 'source_clear')`)
    .bind(binding.mac, rev).all();
  const appVersion = typeof input.app_version === 'string'
    ? input.app_version.replace(/[\u0000-\u001f]/g, '').slice(0, 40) : null;
  for (const order of orders.results || []) {
    const result = await deps.recordAck(env, binding.mac, {
      order_id: order.order_id, state: 'applied', config_rev: rev,
      result: 'config_saved', received_at: now, applied_at: now, app_version: appVersion,
    }, now);
    if (result?.status !== 200 || result?.body?.state !== 'applied') return error('ack_unavailable', 503);
  }
  await deps.markRevisionAck(env, binding.mac, rev, true, 'config_saved', null, now);
  // Le helper historique est best-effort. Ne pas annoncer un succès si
  // sa persistance a échoué : l'app peut réessayer sans réimporter.
  const saved = await env.DB.prepare('SELECT state FROM source_revisions WHERE mac = ? AND rev = ?')
    .bind(binding.mac, rev).first();
  if (saved?.state !== 'acknowledged') return error('ack_unavailable', 503);
  return json({ ok: true, mac: binding.mac, source_rev: rev, result: 'config_saved', orders_acked: (orders.results || []).length });
}

async function readBody(request, limit = BODY_LIMIT) {
  const length = Number(request.headers.get('Content-Length'));
  if (Number.isFinite(length) && length > limit) return { tooLarge: true };
  const reader = request.body?.getReader();
  if (!reader) return { input: null };
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) { await reader.cancel(); return { tooLarge: true }; }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return { input: JSON.parse(new TextDecoder().decode(bytes)) };
}

// readSources(mac) => Promise<Response> est injecté par le Worker afin de
// conserver son format, son coffre de secrets et ses règles de publication.
export async function handleNovatube4k(request, env, deps = {}) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith(PREFIX)) return null;
  const action = path.slice(PREFIX.length);
  const panelAction = Object.hasOwn(PANEL_BODY_LIMITS, action);
  if (!['register', 'state', 'ack'].includes(action) && !panelAction) return error('not_found', 404);
  if (request.method !== 'POST') return error('method_not_allowed', 405);
  if (!env?.DB) return error('storage_unavailable', 503);

  const deviceKey = request.headers.get('X-Device-Key') || '';
  if (!/^[a-f0-9]{64}$/.test(deviceKey)) return error('device_auth_required', 401);
  let input;
  try {
    const result = await readBody(request, panelAction ? PANEL_BODY_LIMITS[action] : BODY_LIMIT);
    if (result.tooLarge) return error('body_too_large', 413);
    input = result.input;
  } catch (_) {
    return error('invalid_json', 400);
  }
  if (!input || typeof input !== 'object' || Array.isArray(input)) return error('invalid_json', 400);
  const raw = normalizeNovatube4kRawMac(input.raw_mac);
  if (!raw) return error('invalid_raw_mac', 400);

  try {
    if (typeof deps.rateLimitOk !== 'function') return error('rate_limit_unavailable', 503);
    const bucket = panelAction ? 'novatube4k-' + action : 'novatube4k';
    const limit = action === 'orders-ack' ? 600 : action === 'blackbox' ? 60 : 240;
    if (!await deps.rateLimitOk(env, request, bucket, limit, 60_000)) return error('rate_limited', 429);
    await ensureSchema(env);
    const keyHash = await sha256(deviceKey);
    if (path.endsWith('/register')) {
      const result = await register(env, raw, keyHash);
      if (result.response) return result.response;
      return await state(env, result.binding, deps, result.created, request);
    }
    const binding = await bindingForRaw(env, raw);
    if (!binding || !sameHash(binding.device_key_hash, keyHash)) return error('device_auth_required', 401);
    if (panelAction) {
      const access = await accessFor(env, binding, Date.now());
      if (!access) return error('device_registration_missing', 409);
      return await handleNovatube4kPanel(action, request, env, binding, input, deps, access);
    }
    if (path.endsWith('/ack')) return await acknowledge(env, binding, input, deps);
    return await state(env, binding, deps, false, request);
  } catch (_) {
    return error('storage_unavailable', 503);
  }
}
