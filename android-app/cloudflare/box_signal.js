// =========================================================
//  box_signal.js — Le panel parle, la box répond
// =========================================================
//  Une action du panel (activer, geler, changer la liste, message…)
//  écrit UNE ligne. La box garde une connexion ouverte (long-polling)
//  et la reçoit dès que la ligne apparaît. Si la connexion tombe,
//  elle reprend avec le dernier numéro déjà reçu : rien n'est perdu,
//  rien n'est appliqué deux fois.
//
//  Le corps ne contient JAMAIS un mot de passe. Seulement :
//    { id, kind, created_at }
//  La box relit ensuite l'état qu'elle connaît déjà (/api/status,
//  annonce, thème…). Les box v102/v103 n'appellent pas ces routes :
//  elles continuent de lire /api/status.
//
//  Jeton de la box : le même header X-Device-Secret que la sauvegarde
//  cloud. Sans ce secret, 401. Le panel, lui, utilise son JWT
//  (GET /api/v1/boxes/live) et ne voit que SES appareils.
// =========================================================

import { secretMatches } from './device_guard.js';

/// Fenêtre « en ligne » pour une box qui tient le canal ouvert.
/// Le serveur garde la connexion 20 s, puis la box la rouvre.
/// 45 s laisse le temps de cette reprise sans la déclarer hors ligne.
export const SIGNAL_ONLINE_MS = 45 * 1000;

/// Ancienne présence (heartbeat), déjà utilisée par la page « En ligne ».
export const LEGACY_ONLINE_MS = 15 * 60 * 1000;

/// Combien de connexions d'attente par minute et par MAC.
/// Une box calme en ouvre environ 3 (une toutes les 20 s). 30 laisse
/// la place à une rafale de clics du panel, et coupe une boucle folle.
export const WAIT_PER_MAC_PER_MIN = 30;

/// Plafond par adresse IP, pour qu'une seule IP ne tienne pas des
/// centaines de connexions ouvertes.
export const WAIT_PER_IP_PER_MIN = 120;

const HOLD_DEFAULT_MS = 20 * 1000;
const HOLD_MIN_MS = 200;
const HOLD_MAX_MS = 20 * 1000;
const TICK_MS = 300;
const SECRET_HEADER = 'X-Device-Secret';

/// Action de l'ancien panel HTML → nom d'ordre pour la box.
/// `note` n'est PAS dedans : c'est une note interne, l'app ne l'affiche pas.
export const ADMIN_ACTION_KIND = {
  freeze: 'suspend',
  unfreeze: 'resume',
  ban: 'block',
  mark_paid: 'activate',
  activate_lifetime: 'activate',
  activate_year: 'activate',
  renew: 'renew',
  mark_unpaid: 'expire',
};

export function kindForAdminAction(action) {
  return ADMIN_ACTION_KIND[action] || null;
}

export function kindForBlock(status) {
  if (status === 'frozen') return 'suspend';
  if (status === 'banned') return 'block';
  return 'resume';
}

/// Durée demandée par la box, bornée. Une valeur absente = 20 s.
export function clampTimeout(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return HOLD_DEFAULT_MS;
  if (n < HOLD_MIN_MS) return HOLD_MIN_MS;
  if (n > HOLD_MAX_MS) return HOLD_MAX_MS;
  return Math.floor(n);
}

/// La box est en ligne si on l'a vue récemment sur le canal,
/// OU si son ancien heartbeat est encore dans la fenêtre de 15 min.
export function isOnline(lastSeenAt, presenceSeen, now) {
  const t = Number(now) || 0;
  const box = Number(lastSeenAt) || 0;
  const old = Number(presenceSeen) || 0;
  if (box > 0 && t - box < SIGNAL_ONLINE_MS) return true;
  if (old > 0 && t - old < LEGACY_ONLINE_MS) return true;
  return false;
}

/// Retire les ordres déjà appliqués (même numéro deux fois = une fois).
export function commandsToApply(items, seenIds) {
  const out = [];
  const local = new Set();
  const seen = seenIds || new Set();
  for (const item of items || []) {
    const id = Number(item && item.id);
    if (!Number.isFinite(id) || seen.has(id) || local.has(id)) continue;
    local.add(id);
    out.push(item);
  }
  return out;
}

/// Heure « 12:03:04 » à partir d'un epoch ms, dans un fuseau donné
/// par les heures/minutes/secondes déjà calculées par l'appelant.
export function clockLabel(hours, minutes, seconds) {
  const p = (n) => String(Math.abs(Number(n) || 0) % 100).padStart(2, '0');
  return `${p(hours)}:${p(minutes)}:${p(seconds)}`;
}

let _ready = false;

export async function ensureSignalSchema(env) {
  if (_ready || !env || !env.DB) return;
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS box_commands (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       mac TEXT NOT NULL,
       kind TEXT NOT NULL,
       created_at INTEGER NOT NULL,
       applied_at INTEGER
     )`,
  ).run();
  await env.DB.prepare(
    'CREATE INDEX IF NOT EXISTS idx_box_commands_mac ON box_commands(mac, id)',
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS fleet_commands (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       kind TEXT NOT NULL,
       created_at INTEGER NOT NULL
     )`,
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS fleet_acks (
       mac TEXT NOT NULL,
       command_id INTEGER NOT NULL,
       applied_at INTEGER NOT NULL,
       PRIMARY KEY (mac, command_id)
     )`,
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS device_secrets (
       mac TEXT PRIMARY KEY,
       secret_hash TEXT NOT NULL,
       android_id TEXT,
       updated_at INTEGER NOT NULL
     )`,
  ).run();
  // Colonnes déjà ajoutées par le heartbeat. On les redemande pour
  // qu'un panel ouvert avant le premier heartbeat ait quand même
  // la version. Un échec (« déjà là ») est ignoré.
  try {
    await env.DB.prepare('ALTER TABLE devices ADD COLUMN app_version TEXT').run();
  } catch (_) { /* déjà là */ }
  try {
    await env.DB.prepare('ALTER TABLE devices ADD COLUMN app_build INTEGER').run();
  } catch (_) { /* déjà là */ }
  _ready = true;
}

/// À n'utiliser que dans les tests qui rejouent le schéma.
export function resetSignalSchemaForTests() {
  _ready = false;
}

const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;

function normMac(mac) {
  const m = String(mac || '').trim().toUpperCase();
  return MAC_RX.test(m) ? m : '';
}

/// Écrit un ordre pour UNE box. N'échoue jamais l'action du panel :
/// si la table tousse, l'état (licence, liste) est déjà enregistré
/// et l'ancienne lecture /api/status le verra quand même.
export async function signalMac(env, mac, kind) {
  try {
    const m = normMac(mac);
    const k = String(kind || '').trim().slice(0, 32);
    if (!env || !env.DB || !m || !k) return;
    await ensureSignalSchema(env);
    await env.DB.prepare(
      'INSERT INTO box_commands (mac, kind, created_at) VALUES (?, ?, ?)',
    ).bind(m, k, Date.now()).run();
  } catch (_) { /* l'action panel reste valide */ }
}

/// Ordre pour TOUTES les box (message, thème, mise à jour forcée…).
export async function signalFleet(env, kind) {
  try {
    const k = String(kind || '').trim().slice(0, 32);
    if (!env || !env.DB || !k) return;
    await ensureSignalSchema(env);
    await env.DB.prepare(
      'INSERT INTO fleet_commands (kind, created_at) VALUES (?, ?)',
    ).bind(k, Date.now()).run();
  } catch (_) { /* idem */ }
}

function clientIp(request) {
  return request.headers.get('CF-Connecting-IP')
    || request.headers.get('X-Forwarded-For')
    || 'unknown';
}

async function allowSlot(env, key, max, windowMs) {
  if (!env || !env.DB) return true;
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS rate_limits (k TEXT PRIMARY KEY, '
      + 'count INTEGER NOT NULL, window_start INTEGER NOT NULL)',
    ).run();
    const now = Date.now();
    const row = await env.DB
      .prepare('SELECT count, window_start FROM rate_limits WHERE k = ?')
      .bind(key).first();
    if (!row || (now - row.window_start) > windowMs) {
      await env.DB.prepare(
        'INSERT INTO rate_limits (k, count, window_start) VALUES (?, 1, ?) '
        + 'ON CONFLICT(k) DO UPDATE SET count = 1, window_start = ?',
      ).bind(key, now, now).run();
      return true;
    }
    if (row.count >= max) return false;
    await env.DB.prepare('UPDATE rate_limits SET count = count + 1 WHERE k = ?')
      .bind(key).run();
    return true;
  } catch (_) {
    return true;
  }
}

function json(body, status = 200, extra) {
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  };
  if (extra) {
    for (const [k, v] of Object.entries(extra)) headers[k] = v;
  }
  return new Response(JSON.stringify(body), { status, headers });
}

/// Secret enregistré ET présenté. Sinon 401 : la MAC affichée
/// à l'écran ne suffit pas à écouter les ordres.
async function boxAuthed(env, request, mac) {
  await ensureSignalSchema(env);
  const row = await env.DB.prepare(
    'SELECT secret_hash FROM device_secrets WHERE mac = ?',
  ).bind(mac).first();
  const hash = row && row.secret_hash ? String(row.secret_hash) : '';
  if (!hash) return false;
  const presented = request.headers.get(SECRET_HEADER) || '';
  return secretMatches(presented, hash);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readPending(env, mac, boxAfter, fleetAfter) {
  const boxRs = await env.DB.prepare(
    `SELECT id, kind, created_at FROM box_commands
     WHERE mac = ? AND id > ? AND applied_at IS NULL
     ORDER BY id ASC LIMIT 20`,
  ).bind(mac, boxAfter).all();
  const fleetRs = await env.DB.prepare(
    `SELECT f.id AS id, f.kind AS kind, f.created_at AS created_at
     FROM fleet_commands f
     WHERE f.id > ?
       AND NOT EXISTS (
         SELECT 1 FROM fleet_acks a
         WHERE a.mac = ? AND a.command_id = f.id
       )
     ORDER BY f.id ASC LIMIT 20`,
  ).bind(fleetAfter, mac).all();
  const box = (boxRs && boxRs.results) || [];
  const fleet = (fleetRs && fleetRs.results) || [];
  return {
    box: box.map(publicRow),
    fleet: fleet.map(publicRow),
  };
}

function publicRow(row) {
  return {
    id: Number(row.id) || 0,
    kind: String(row.kind || ''),
    created_at: Number(row.created_at) || 0,
  };
}

async function touchPresence(env, mac, version, build) {
  const now = Date.now();
  try {
    await env.DB.prepare(
      'UPDATE devices SET last_seen_at = ? WHERE mac = ?',
    ).bind(now, mac).run();
  } catch (_) { /* la box peut attendre avant d'avoir une fiche */ }
  const v = String(version || '').trim().slice(0, 24);
  const b = parseInt(build, 10) || 0;
  if (!v && !b) return;
  try {
    await env.DB.prepare(
      'UPDATE devices SET '
      + "app_version = CASE WHEN ? != '' THEN ? ELSE app_version END, "
      + 'app_build = CASE WHEN ? != 0 THEN ? ELSE app_build END '
      + 'WHERE mac = ?',
    ).bind(v, v, b, b, mac).run();
  } catch (_) { /* colonne pas encore là : la présence suffit */ }
}

/// GET /api/box/wait/:mac?after=&fleet_after=&timeout=&v=&b=
export async function handleBoxWait(request, env, macRaw) {
  if (!env || !env.DB) {
    return json({ error: 'unavailable', message: 'Base indisponible.' }, 503);
  }
  const mac = normMac(decodeURIComponent(macRaw || ''));
  if (!mac) return json({ error: 'bad_mac', message: 'MAC invalide.' }, 400);
  const authed = await boxAuthed(env, request, mac);
  if (!authed) {
    return json({
      error: 'device_secret_required',
      message: 'Secret de la box requis.',
    }, 401);
  }
  const ipOk = await allowSlot(
    env, `sigip:${clientIp(request)}`, WAIT_PER_IP_PER_MIN, 60 * 1000,
  );
  const macOk = await allowSlot(
    env, `sig:${mac}`, WAIT_PER_MAC_PER_MIN, 60 * 1000,
  );
  if (!ipOk || !macOk) {
    return json({
      error: 'rate_limited',
      message: 'Trop de connexions, réessaie dans un instant.',
    }, 429, { 'Retry-After': '30' });
  }

  const url = new URL(request.url);
  const boxAfter = Math.max(0, parseInt(url.searchParams.get('after') || '0', 10) || 0);
  const fleetAfter = Math.max(0, parseInt(url.searchParams.get('fleet_after') || '0', 10) || 0);
  const hold = clampTimeout(url.searchParams.get('timeout'));
  await touchPresence(
    env, mac, url.searchParams.get('v'), url.searchParams.get('b'),
  );

  const deadline = Date.now() + hold;
  while (true) {
    const pending = await readPending(env, mac, boxAfter, fleetAfter);
    if (pending.box.length || pending.fleet.length) {
      return json({ ok: true, timeout: false, ...pending });
    }
    const left = deadline - Date.now();
    if (left <= 0) {
      return json({
        ok: true, timeout: true, box: [], fleet: [],
      });
    }
    await sleep(Math.min(TICK_MS, left));
  }
}

function idList(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const x of raw) {
    const n = Number(x);
    if (Number.isFinite(n) && n > 0) out.push(Math.floor(n));
  }
  return out.slice(0, 40);
}

/// POST /api/box/ack/:mac  { box: [ids], fleet: [ids] }
/// Le premier accusé grave l'heure. Le deuxième ne la change pas.
export async function handleBoxAck(request, env, macRaw) {
  if (!env || !env.DB) {
    return json({ error: 'unavailable', message: 'Base indisponible.' }, 503);
  }
  const mac = normMac(decodeURIComponent(macRaw || ''));
  if (!mac) return json({ error: 'bad_mac', message: 'MAC invalide.' }, 400);
  const authed = await boxAuthed(env, request, mac);
  if (!authed) {
    return json({
      error: 'device_secret_required',
      message: 'Secret de la box requis.',
    }, 401);
  }
  let body = {};
  try { body = await request.json(); } catch (_) { body = {}; }
  const boxIds = idList(body.box);
  const fleetIds = idList(body.fleet);
  const now = Date.now();
  let fresh = 0;
  let appliedAt = 0;
  for (const id of boxIds) {
    const cur = await env.DB.prepare(
      'SELECT applied_at FROM box_commands WHERE mac = ? AND id = ?',
    ).bind(mac, id).first();
    if (!cur) continue;
    if (cur.applied_at) {
      appliedAt = Number(cur.applied_at) || appliedAt;
      continue;
    }
    await env.DB.prepare(
      'UPDATE box_commands SET applied_at = ? WHERE mac = ? AND id = ? AND applied_at IS NULL',
    ).bind(now, mac, id).run();
    fresh += 1;
    appliedAt = now;
  }
  for (const id of fleetIds) {
    const cur = await env.DB.prepare(
      'SELECT applied_at FROM fleet_acks WHERE mac = ? AND command_id = ?',
    ).bind(mac, id).first();
    if (cur && cur.applied_at) {
      appliedAt = Number(cur.applied_at) || appliedAt;
      continue;
    }
    const exists = await env.DB.prepare(
      'SELECT id FROM fleet_commands WHERE id = ?',
    ).bind(id).first();
    if (!exists) continue;
    await env.DB.prepare(
      'INSERT INTO fleet_acks (mac, command_id, applied_at) VALUES (?, ?, ?)',
    ).bind(mac, id, now).run();
    fresh += 1;
    appliedAt = now;
  }
  return json({
    ok: true,
    applied_at: appliedAt || null,
    already: fresh === 0,
  });
}

/// Vue panel : en ligne, version, dernier ordre appliqué ou en attente.
/// `restrictReseller` = id du revendeur, ou null pour l'admin.
export async function loadBoxLive(env, { restrictReseller, mac }) {
  await ensureSignalSchema(env);
  const want = normMac(mac || '');
  let sql = `SELECT d.id AS id, d.mac AS mac, d.label AS label,
                    d.reseller_id AS reseller_id,
                    d.last_seen_at AS last_seen_at,
                    d.block_status AS block_status,
                    d.app_version AS app_version,
                    d.app_build AS app_build
             FROM devices d`;
  const binds = [];
  const where = [];
  if (restrictReseller) {
    where.push('d.reseller_id = ?');
    binds.push(restrictReseller);
  }
  if (want) {
    where.push('d.mac = ?');
    binds.push(want);
  }
  if (where.length) sql += ' WHERE ' + where.join(' AND ');
  sql += ' ORDER BY d.last_seen_at DESC LIMIT 200';
  const rs = await env.DB.prepare(sql).bind(...binds).all();
  const devices = (rs && rs.results) || [];
  const now = Date.now();

  const pendingRs = await env.DB.prepare(
    `SELECT mac, id, kind, created_at FROM box_commands
     WHERE applied_at IS NULL ORDER BY id ASC LIMIT 500`,
  ).all();
  const lastRs = await env.DB.prepare(
    `SELECT c.mac AS mac, c.id AS id, c.kind AS kind, c.applied_at AS applied_at
     FROM box_commands c
     INNER JOIN (
       SELECT mac, MAX(id) AS id FROM box_commands
       WHERE applied_at IS NOT NULL GROUP BY mac
     ) t ON t.id = c.id`,
  ).all();
  const fleetRs = await env.DB.prepare(
    'SELECT id, kind, created_at FROM fleet_commands ORDER BY id DESC LIMIT 30',
  ).all();
  const ackRs = await env.DB.prepare(
    `SELECT a.mac AS mac, a.command_id AS command_id, a.applied_at AS applied_at,
            f.kind AS kind
     FROM fleet_acks a
     JOIN fleet_commands f ON f.id = a.command_id`,
  ).all();

  let presence = [];
  try {
    const p = await env.DB.prepare(
      'SELECT mac, last_seen FROM presence',
    ).all();
    presence = (p && p.results) || [];
  } catch (_) { presence = []; }

  const pendingByMac = group(pendingRs && pendingRs.results, 'mac');
  const lastByMac = new Map();
  for (const row of (lastRs && lastRs.results) || []) {
    lastByMac.set(row.mac, row);
  }
  const presenceByMac = new Map();
  for (const row of presence) presenceByMac.set(row.mac, row.last_seen);
  const fleet = ((fleetRs && fleetRs.results) || []).map(publicRow).reverse();
  const acksByMac = new Map();
  for (const row of (ackRs && ackRs.results) || []) {
    const list = acksByMac.get(row.mac) || [];
    list.push(row);
    acksByMac.set(row.mac, list);
  }

  return {
    now,
    items: devices.map((d) => {
      const acks = acksByMac.get(d.mac) || [];
      const ackedIds = new Set(acks.map((a) => Number(a.command_id)));
      let fleetLast = null;
      for (const a of acks) {
        if (!fleetLast || Number(a.command_id) > Number(fleetLast.command_id)) {
          fleetLast = a;
        }
      }
      const fleetPending = fleet.filter((f) => !ackedIds.has(f.id));
      const last = lastByMac.get(d.mac);
      return {
        id: d.id,
        mac: d.mac,
        label: d.label || null,
        online: isOnline(d.last_seen_at, presenceByMac.get(d.mac), now),
        last_seen_at: Number(d.last_seen_at) || 0,
        app_version: d.app_version || '',
        app_build: Number(d.app_build) || 0,
        block_status: d.block_status || null,
        pending: (pendingByMac.get(d.mac) || []).map(publicRow),
        last_applied: last ? {
          id: Number(last.id) || 0,
          kind: String(last.kind || ''),
          applied_at: Number(last.applied_at) || 0,
        } : null,
        fleet_pending: fleetPending,
        fleet_last_applied: fleetLast ? {
          id: Number(fleetLast.command_id) || 0,
          kind: String(fleetLast.kind || ''),
          applied_at: Number(fleetLast.applied_at) || 0,
        } : null,
      };
    }),
  };
}

function group(rows, key) {
  const map = new Map();
  for (const row of rows || []) {
    const k = row[key];
    const list = map.get(k) || [];
    list.push(row);
    map.set(k, list);
  }
  return map;
}
