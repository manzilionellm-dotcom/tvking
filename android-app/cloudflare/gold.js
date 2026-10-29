// 7 MOTION x GOLD/Strong panel (cms-8k.net API v1.81) — wrapper module.
// Main module: wraps the unchanged production bundle (./worker.js).
import orig, { goldSealSource, goldOpenSourceList, goldNotifyBox } from './production/worker.runtime.js';
export { RealtimeHub } from './gold_realtime.js';
import { createRealtimeRoutes, globalPanelChange, pushPanelSettingChange } from './gold_realtime.js';
import { activationDeliveryState } from './gold_activation_delivery.js';
import { createTrialRuntime } from './gold_trial_runtime.js';
import { sourceEncryptionEnv } from './gold_trial_delivery.js';
import { createGoldenRoutes, goldenTemplates, protectGoldenSource } from './gold_golden.js';
import { createGoldenDelivery } from './gold_golden_delivery.js';

const GOLD_BASE = 'https://cms-8k.net/api/api.php';
const ALL_PACKS = '84802,84803,84804,84805,84806,84807,84808,84810,84811,84813,84814,84815,84816';
const DEFAULTS = {
  gold_enabled: '0', gold_trial_enabled: '0', gold_max_per_day: '5', gold_min_credits: '5',
  gold_default_sub: '12', gold_pack: ALL_PACKS, gold_trial_max_per_day: '20', gold_trial_sub: '99', gold_cost_per_month: '1',
};
const CONFIG_KEYS = Object.keys(DEFAULTS);
const MAC_RE = /^MK(?::[0-9A-F]{2}){5}$/;
const DAY_MS = 86400000;

const J = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
});
const rid = (p) => p + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);

export function normMac(raw) {
  let s = decodeURIComponent(String(raw || '')).trim().toUpperCase().replace(/[-.]/g, ':');
  if (!s.startsWith('MK')) {
    const hex = s.replace(/[^0-9A-F]/g, '');
    if (hex.length === 12) s = 'MK:' + hex.match(/../g).join(':');
  } else {
    const hex = s.slice(2).replace(/[^0-9A-F]/g, '');
    if (hex.length === 10) s = 'MK:' + hex.match(/../g).join(':');
  }
  return MAC_RE.test(s) ? s : null;
}

let _ddl = new WeakSet();
async function ensureTables(env) {
  if (_ddl.has(env.DB)) return;
  await env.DB.batch([
    env.DB.prepare('CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT)'),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS gold_lines (
      id TEXT PRIMARY KEY, mac TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
      gold_user_id TEXT, username TEXT, password TEXT, url TEXT, sub INTEGER, expire TEXT,
      android_id TEXT, ip TEXT, app_version TEXT, created_by TEXT, error TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)`),
    env.DB.prepare('CREATE UNIQUE INDEX IF NOT EXISTS ux_gold_lines_mac_kind ON gold_lines(mac, kind)'),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS gold_history (
      id TEXT PRIMARY KEY, mac TEXT NOT NULL, event TEXT NOT NULL, gold_line_id TEXT,
      gold_user_id TEXT, sub INTEGER, expire TEXT, ip TEXT, app_version TEXT, actor TEXT,
      detail_json TEXT, created_at INTEGER NOT NULL)`),
    env.DB.prepare('CREATE INDEX IF NOT EXISTS ix_gold_history_mac ON gold_history(mac, created_at)'),
  ]);
  _ddl.add(env.DB);
}

async function getConfig(env) {
  const { results } = await env.DB.prepare(
    `SELECT key, value FROM app_config WHERE key IN (${CONFIG_KEYS.map(() => '?').join(',')})`,
  ).bind(...CONFIG_KEYS).all();
  const c = { ...DEFAULTS };
  for (const r of results || []) c[r.key] = r.value;
  return c;
}

async function history(env, mac, event, f = {}) {
  try {
    await env.DB.prepare(`INSERT INTO gold_history (id, mac, event, gold_line_id, gold_user_id, sub, expire,
      ip, app_version, actor, detail_json, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`)
      .bind(rid('gh'), mac, event, f.line_id || null, f.gold_user_id || null, f.sub ?? null, f.expire || null,
        f.ip || null, f.app_version || null, f.actor || null, f.detail ? JSON.stringify(f.detail) : null, Date.now())
      .run();
  } catch (e) { console.log('gold.history_failed', String(e && e.message)); }
}

async function audit(env, actorId, action, mac, after) {
  try {
    await env.DB.prepare(`INSERT INTO audit_logs (id, actor_type, actor_id, action, target_type, target_id,
      before_json, after_json, ip, user_agent, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)`)
      .bind(rid('aud'), actorId && actorId.startsWith('device:') ? 'customer' : 'admin', actorId || 'system',
        action, 'gold_line', mac, null, JSON.stringify(after || {}), null, 'gold-integration', Date.now()).run();
  } catch (e) { console.log('gold.audit_failed', String(e && e.message)); }
}

// ---- Gold API (key never logged / returned) ----
async function aesKey(env) {
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('gold-key-v1:' + String(env.ADMIN_SECRET || '')));
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
async function storeKey(env, key) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await aesKey(env), new TextEncoder().encode(key));
  const v = b64u(iv) + '.' + b64u(ct);
  await env.DB.prepare("INSERT INTO app_config (key,value) VALUES ('gold_key_enc',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").bind(v).run();
}
let _keyCache = null;
async function getKey(env) {
  const s = String(env.GOLD_PANEL_API_KEY || '');
  if (s.length >= 20 && !s.startsWith('[')) return s;
  if (_keyCache) return _keyCache;
  const row = await env.DB.prepare("SELECT value FROM app_config WHERE key='gold_key_enc'").first();
  if (!row) return null;
  const d = (x) => Uint8Array.from(atob(x.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((x.length + 3) % 4)), (c) => c.charCodeAt(0));
  const [iv, ct] = row.value.split('.');
  _keyCache = new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: d(iv) }, await aesKey(env), d(ct)));
  return _keyCache;
}

// ---- multi-key pool (encrypted in D1) ----
let _poolDdl = new WeakSet();
async function ensurePool(env) {
  if (_poolDdl.has(env.DB)) return;
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS gold_keys (
    id TEXT PRIMARY KEY, enc TEXT NOT NULL, fp TEXT NOT NULL UNIQUE, reseller TEXT, masked TEXT,
    trial_priority INTEGER NOT NULL DEFAULT 10, use_for_paid INTEGER NOT NULL DEFAULT 0,
    trial_cap_per_day INTEGER, pack TEXT, enabled INTEGER NOT NULL DEFAULT 1,
    last_error TEXT, last_used_at INTEGER, created_at INTEGER NOT NULL)`).run();
  try { await env.DB.prepare('ALTER TABLE gold_lines ADD COLUMN key_id TEXT').run(); } catch (_) {}
  _poolDdl.add(env.DB);
  const n = (await env.DB.prepare('SELECT COUNT(*) n FROM gold_keys').first()).n;
  if (n === 0) {
    const legacy = await getKey(env).catch(() => null);
    if (legacy) await addKey(env, legacy, { trial_priority: 20, use_for_paid: 1, pack: null, reseller: null });
  }
}
async function encStr(env, k) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await aesKey(env), new TextEncoder().encode(k));
  return b64u(iv) + '.' + b64u(ct);
}
async function decStr(env, v) {
  const d = (x) => Uint8Array.from(atob(x.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((x.length + 3) % 4)), (c) => c.charCodeAt(0));
  const [iv, ct] = v.split('.');
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: d(iv) }, await aesKey(env), d(ct)));
}
async function keyFp(k) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(k)))].slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('');
}
async function addKey(env, k, o = {}) {
  const fp = await keyFp(k);
  const id = rid('gk');
  await env.DB.prepare(`INSERT INTO gold_keys (id, enc, fp, reseller, masked, trial_priority, use_for_paid, trial_cap_per_day, pack, enabled, created_at)
    VALUES (?,?,?,?,?,?,?,?,?,1,?) ON CONFLICT(fp) DO UPDATE SET reseller=COALESCE(excluded.reseller, gold_keys.reseller)`)
    .bind(id, await encStr(env, k), fp, o.reseller || null, k.slice(0, 3) + '…' + k.slice(-3), o.trial_priority ?? 10,
      o.use_for_paid ? 1 : 0, o.trial_cap_per_day ?? null, o.pack || null, Date.now()).run();
  return (await env.DB.prepare('SELECT id FROM gold_keys WHERE fp=?').bind(fp).first()).id;
}
async function poolKeys(env, purpose) {
  await ensurePool(env);
  const q = purpose === 'paid'
    ? 'SELECT * FROM gold_keys WHERE enabled=1 AND use_for_paid=1 ORDER BY trial_priority, created_at'
    : 'SELECT * FROM gold_keys WHERE enabled=1 ORDER BY trial_priority, created_at';
  const rows = (await env.DB.prepare(q).all()).results || [];
  const out = [];
  for (const r of rows) { try { out.push({ ...r, key: await decStr(env, r.enc) }); } catch (_) {} }
  return out;
}
async function keyById(env, id) {
  await ensurePool(env);
  const r = id ? await env.DB.prepare('SELECT * FROM gold_keys WHERE id=?').bind(id).first() : null;
  if (r) return { ...r, key: await decStr(env, r.enc) };
  return (await poolKeys(env, 'paid'))[0] || (await poolKeys(env, 'trial'))[0] || null;
}
async function keyTrialsToday(env, keyId) {
  return (await env.DB.prepare("SELECT COUNT(*) n FROM gold_lines WHERE key_id=? AND kind IN ('trial','demo') AND status IN ('active','pending') AND created_at >= ?")
    .bind(keyId, dayStart()).first()).n;
}
const publicKey = (r, extra = {}) => ({ id: r.id, reseller: r.reseller, masked: r.masked, trial_priority: r.trial_priority,
  use_for_paid: !!r.use_for_paid, trial_cap_per_day: r.trial_cap_per_day, pack: r.pack, enabled: !!r.enabled,
  last_error: r.last_error, last_used_at: r.last_used_at, ...extra });

async function goldCall(env, params, keyOverride, timeoutMs = 45000) {
  const key = keyOverride || await getKey(env);
  if (!key) throw new Error('gold_key_missing');
  const qs = new URLSearchParams({ ...params, api_key: key });
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const r = await fetch(`${GOLD_BASE}?${qs}`, { signal: ctl.signal, headers: { accept: 'application/json' } });
    if (!r.ok) throw new Error('gold_http_error');
    const txt = await r.text();
    let data; try { data = JSON.parse(txt); } catch (_) { throw new Error('gold_bad_json'); }
    return data;
  } finally { clearTimeout(t); }
}
const first = (d) => (Array.isArray(d) ? d[0] : d) || {};
const ok = (d) => { const x = first(d); return x.status === true || x.status === 'true'; };

async function goldCredits(env, key) {
  const d = first(await goldCall(env, { action: 'reseller' }, key));
  if (!ok(d)) throw new Error('gold_reseller_failed: ' + String(d.message || d.result || JSON.stringify(d)).slice(0, 160));
  return { username: d.username, credits: Number(d.credits) };
}

function parseLineUrl(u) {
  try {
    const x = new URL(u);
    const username = x.searchParams.get('username'), password = x.searchParams.get('password');
    if (!username || !password) return null;
    return { server_url: x.origin, username, password };
  } catch (_) { return null; }
}

// ---- internal admin token to reuse the existing /api/v1/sources handler ----
const b64u = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
async function internalAdminToken(env) {
  const secret = String(env.ADMIN_SECRET || '').trim();
  const adm = await env.DB.prepare("SELECT id, email FROM admin_users WHERE role = 'super_admin' AND is_active = 1 ORDER BY created_at LIMIT 1").first();
  if (!secret || !adm) throw new Error('no_admin');
  const now = Math.floor(Date.now() / 1000);
  const enc = (o) => b64u(new TextEncoder().encode(JSON.stringify(o)));
  const h = enc({ alg: 'HS256', typ: 'JWT' });
  const p = enc({ sub: adm.id, email: adm.email, role: 'super_admin', iat: now, exp: now + 120 });
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = b64u(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${sig}`;
}

async function deliverToDevice(env, ctx, mac, creds, label, traceId) {
  const token = await internalAdminToken(env);
  const auth = { Authorization: `Bearer ${token}`, 'content-type': 'application/json' };
  if (typeof traceId === 'string' && /^[A-Za-z0-9_.:-]{8,64}$/.test(traceId)) auth['X-Request-Id'] = traceId;
  const path = `https://internal/api/v1/sources/${encodeURIComponent(mac)}`;
  let keep = [];
  try {
    const g = await orig.fetch(new Request(path, { headers: auth }), env, ctx);
    if (g.ok) {
      const j = await g.json();
      keep = (j.sources || []).filter((s) => s && s.origin !== 'self' && s.username !== creds.username)
        .map((s) => ({ type: s.type, label: s.label, server_url: s.server_url, username: s.username,
          password: s.password, m3u_url: s.m3u_url, epg_url: s.epg_url, ...(s.enabled === false ? { enabled: false } : {}) }));
    }
  } catch (_) { keep = []; }
  const sources = [{ type: 'xtream', label, ...creds }, ...keep].slice(0, 3);
  const r = await orig.fetch(new Request(path, { method: 'PUT', headers: auth, body: JSON.stringify({ sources }) }), env, ctx);
  const body = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, rev: body.rev, order_id: body.order_id, error: body.error };
}

const dayStart = () => { const n = Date.now(); return n - (n % DAY_MS); };

// ---- core provisioning (all guards) ----
// kind: 'paid' (credits), 'trial' (device button, demo ticket), 'demo' (admin test, demo ticket)
async function provision(env, ctx, o) {
  const { kind, actor, dryRun = false } = o;
  // L'ancienne voie action=new/sub=99 ne doit plus créer AUCUNE démo.
  // La voie payante existante reste séparée et conserve ses contrôles.
  if (kind !== 'paid') return { http: 503, error: 'demo_contract_unverified',
    message: 'La création de démos est suspendue jusqu’à validation du contrat fournisseur.' };
  const mac = normMac(o.mac);
  if (!mac) return { http: 400, error: 'bad_mac' };
  const cfg = await getConfig(env);
  const sub = kind === 'paid' ? Math.max(1, Math.min(12, Number(o.sub || cfg.gold_default_sub) || 12)) : Number(cfg.gold_trial_sub || 99);
  if (kind === 'paid' && ![1, 3, 6, 12].includes(sub)) return { http: 400, error: 'bad_sub' };
  const checks = {};
  checks.enabled = kind === 'paid' ? cfg.gold_enabled === '1' : kind === 'trial' ? cfg.gold_trial_enabled === '1' : true;
  if (!checks.enabled && !dryRun) {
    return { http: 403, error: kind === 'trial' ? 'trial_disabled' : 'gold_disabled', checks };
  }
  const existing = await env.DB.prepare('SELECT * FROM gold_lines WHERE mac = ? AND kind = ?').bind(mac, kind).first();
  if (existing && existing.status === 'active') {
    if (kind === 'trial') await history(env, mac, 'trial.refused', { line_id: existing.id, ip: o.ip, app_version: o.appVersion, actor, detail: { reason: 'already_used' } });
    return { http: kind === 'trial' ? 409 : 200, error: kind === 'trial' ? 'trial_already_used' : undefined,
      idempotent: true, charged: false, line: publicLine(existing) };
  }
  if (existing && existing.status === 'pending' && Date.now() - existing.updated_at < 120000) {
    return { http: 409, error: 'in_progress' };
  }
  const capKey = kind === 'trial' ? 'gold_trial_max_per_day' : 'gold_max_per_day';
  const cap = Number(cfg[capKey]);
  const usedToday = (await env.DB.prepare("SELECT COUNT(*) n FROM gold_lines WHERE kind = ? AND status IN ('active','pending') AND created_at >= ?")
    .bind(kind === 'demo' ? 'demo' : kind, dayStart()).first()).n;
  checks.daily = { used: usedToday, cap: kind === 'demo' ? 3 : cap };
  if (usedToday >= checks.daily.cap) {
    await audit(env, actor, 'gold.blocked.daily_cap', mac, { kind, used: usedToday, cap: checks.daily.cap });
    return { http: 429, error: 'daily_cap_reached', checks };
  }
  // candidate keys (paid: use_for_paid keys; trial/demo: all keys by trial priority, per-key daily cap)
  const keys = await poolKeys(env, kind === 'paid' ? 'paid' : 'trial');
  if (!keys.length) return { http: 503, error: 'no_gold_key' };
  const est = kind === 'paid' ? sub * Number(cfg.gold_cost_per_month || 1) : 0;
  const tried = [];
  const eligible = [];
  for (const k of keys) {
    const t = { key_id: k.id, reseller: k.reseller };
    if (kind !== 'paid' && k.trial_cap_per_day != null) {
      const usedK = await keyTrialsToday(env, k.id);
      t.trials_today = usedK; t.cap = k.trial_cap_per_day;
      if (usedK >= k.trial_cap_per_day) { t.skip = 'key_daily_cap'; tried.push(t); continue; }
    }
    try { const c = await goldCredits(env, k.key); t.credits = c.credits; k.credits = c.credits; if (!k.reseller && c.username) k.reseller = c.username; }
    catch (e) { t.skip = 'credit_check_failed'; t.error = String(e.message).slice(0, 120); tried.push(t); continue; }
    if (kind === 'paid' && k.credits - est < Number(cfg.gold_min_credits)) { t.skip = 'credit_floor'; tried.push(t); continue; }
    tried.push(t); eligible.push(k);
  }
  checks.keys = tried;
  if (!eligible.length) {
    const why = kind === 'paid' && tried.some((t) => t.skip === 'credit_floor') ? 'credit_floor' : 'no_key_available';
    await audit(env, actor, `gold.blocked.${why}`, mac, { kind, tried });
    return { http: why === 'credit_floor' ? 402 : 503, error: why, checks };
  }
  if (kind === 'paid') checks.floor = { min: Number(cfg.gold_min_credits), estimated_cost: est, after: eligible[0].credits - est };
  checks.credits = eligible[0].credits;
  if (dryRun) return { http: 200, dry_run: true, would: existing ? 'retry' : 'create', mac, kind, sub, use_key: { id: eligible[0].id, reseller: eligible[0].reseller }, failover: eligible.slice(1).map((k) => k.reseller || k.id), checks };

  // atomic claim (idempotency: one line per mac+kind; trial = forever, global across keys)
  const now = Date.now();
  const id = existing ? existing.id : rid('gl');
  let claimed;
  if (existing) {
    claimed = await env.DB.prepare("UPDATE gold_lines SET status='pending', updated_at=? WHERE id=? AND status IN ('failed','pending') AND updated_at=?")
      .bind(now, id, existing.updated_at).run();
  } else {
    claimed = await env.DB.prepare(`INSERT INTO gold_lines (id, mac, kind, status, sub, android_id, ip, app_version, created_by, created_at, updated_at)
      VALUES (?,?,?,'pending',?,?,?,?,?,?,?) ON CONFLICT(mac, kind) DO NOTHING`)
      .bind(id, mac, kind, sub, o.androidId || null, o.ip || null, o.appVersion || null, actor || null, now, now).run();
  }
  if (!claimed.meta || claimed.meta.changes !== 1) return { http: 409, error: 'in_progress' };

  let res = null, creds = null, used = null, before = null;
  const attempts = [];
  for (const k of eligible) {
    let r;
    try {
      r = first(await goldCall(env, { action: 'new', type: 'm3u', sub: String(sub), pack: k.pack || (k.use_for_paid ? (cfg.gold_pack || ALL_PACKS) : 'all'), note: `7M ${kind} ${mac}` }, k.key));
    } catch (e) { r = { status: 'error', message: String(e.message) }; }
    const c = ok(r) ? parseLineUrl(r.url) : null;
    const msg = String(r.message || r.result || '').slice(0, 200);
    attempts.push({ key_id: k.id, reseller: k.reseller, ok: !!c, message: c ? undefined : msg });
    await env.DB.prepare('UPDATE gold_keys SET last_used_at=?, last_error=?, reseller=COALESCE(reseller, ?) WHERE id=?')
      .bind(Date.now(), c ? null : msg, k.reseller || null, k.id).run();
    if (c) { res = r; creds = c; used = k; before = { credits: k.credits }; break; }
    // paid: never fail over on an ambiguous error after a possible charge — only on clear refusals
    if (kind === 'paid' && !/not found|invalid|insufficient|not enough|credit|disabled|missing/i.test(msg)) break;
  }
  if (!creds) {
    const last = attempts[attempts.length - 1] || {};
    await env.DB.prepare("UPDATE gold_lines SET status='failed', error=?, updated_at=? WHERE id=?")
      .bind(String(last.message || 'gold_error').slice(0, 300), Date.now(), id).run();
    await audit(env, actor, `gold.${kind}.failed`, mac, { attempts });
    await history(env, mac, `${kind}.failed`, { line_id: id, ip: o.ip, app_version: o.appVersion, actor, detail: { attempts } });
    return { http: 502, error: 'gold_create_failed', message: last.message, attempts };
  }
  await env.DB.prepare('UPDATE gold_lines SET key_id=? WHERE id=?').bind(used.id, id).run();
  let expire = null;
  try { const di = first(await goldCall(env, { action: 'device_info', username: creds.username, password: creds.password }, used.key)); expire = di.expire || null; } catch (_) {}
  await env.DB.prepare("UPDATE gold_lines SET status='active', gold_user_id=?, username=?, password=?, url=?, expire=?, error=NULL, updated_at=? WHERE id=?")
    .bind(String(res.user_id || ''), creds.username, creds.password, String(res.url), expire, Date.now(), id).run();
  let after = null;
  try { after = await goldCredits(env, used.key); } catch (_) {}
  const spent = after ? before.credits - after.credits : null;
  if (kind !== 'paid' && spent && spent > 0) {
    // safety: a trial/demo must never cost credits -> kill switch
    await env.DB.prepare("INSERT INTO app_config (key,value) VALUES ('gold_trial_enabled','0') ON CONFLICT(key) DO UPDATE SET value='0'").run();
    await env.DB.prepare('UPDATE gold_keys SET last_error=? WHERE id=?').bind('ALERT: trial spent credits', used.id).run();
    await audit(env, 'system', 'gold.alert.trial_spent_credits', mac, { spent, key_id: used.id });
  }
  const delivery = await deliverToDevice(env, ctx, mac, creds, kind === 'paid' ? '7 MOTION' : '7 MOTION Essai', o.traceId).catch((e) => ({ ok: false, error: String(e.message) }));
  await audit(env, actor, `gold.${kind}.create`, mac, { line_id: id, gold_user_id: res.user_id, sub, expire, credits_before: before.credits, credits_after: after && after.credits, delivered: delivery.ok });
  await history(env, mac, `${kind}.create`, { line_id: id, gold_user_id: res.user_id, sub, expire, ip: o.ip, app_version: o.appVersion, actor,
    detail: { key_id: used.id, reseller: used.reseller, attempts, credits_before: before.credits, credits_after: after && after.credits, delivered: delivery.ok, order_id: delivery.order_id } });
  return { http: 201, created: true, mac, kind, sub, expire, credits_before: before.credits, credits_after: after && after.credits,
    key: { id: used.id, reseller: used.reseller }, attempts, spent, delivery, line: { id, gold_user_id: String(res.user_id || ''), username: creds.username, expire } };
}

function publicLine(r) {
  return r && { id: r.id, mac: r.mac, kind: r.kind, status: r.status, gold_user_id: r.gold_user_id, username: r.username,
    sub: r.sub, expire: r.expire, created_at: r.created_at, updated_at: r.updated_at, error: r.error };
}

async function renew(env, ctx, mac, sub, actor) {
  mac = normMac(mac); if (!mac) return { http: 400, error: 'bad_mac' };
  const cfg = await getConfig(env);
  if (cfg.gold_enabled !== '1') return { http: 403, error: 'gold_disabled' };
  sub = Number(sub || cfg.gold_default_sub); if (![1, 3, 6, 12].includes(sub)) return { http: 400, error: 'bad_sub' };
  const line = await env.DB.prepare("SELECT * FROM gold_lines WHERE mac=? AND kind='paid' AND status='active'").bind(mac).first();
  if (!line) return { http: 404, error: 'no_paid_line' };
  const k = await keyById(env, line.key_id);
  if (!k) return { http: 503, error: 'no_gold_key' };
  const c = await goldCredits(env, k.key);
  const est = sub * Number(cfg.gold_cost_per_month || 1);
  if (c.credits - est < Number(cfg.gold_min_credits)) return { http: 402, error: 'credit_floor', credits: c.credits };
  const r = first(await goldCall(env, { action: 'renew', type: 'm3u', username: line.username, password: line.password, sub: String(sub) }, k.key));
  if (!ok(r)) return { http: 502, error: 'gold_renew_failed', message: r.message || r.result };
  let expire = line.expire;
  try { expire = first(await goldCall(env, { action: 'device_info', username: line.username, password: line.password }, k.key)).expire || expire; } catch (_) {}
  await env.DB.prepare('UPDATE gold_lines SET expire=?, sub=?, updated_at=? WHERE id=?').bind(expire, sub, Date.now(), line.id).run();
  await audit(env, actor, 'gold.paid.renew', mac, { line_id: line.id, sub, expire });
  await history(env, mac, 'paid.renew', { line_id: line.id, gold_user_id: line.gold_user_id, sub, expire, actor });
  return { http: 200, renewed: true, mac, sub, expire };
}

async function sync(env, actor) {
  const { results } = await env.DB.prepare("SELECT * FROM gold_lines WHERE status='active' ORDER BY updated_at LIMIT 50").all();
  const out = [];
  for (const l of results || []) {
    try {
      const kk = await keyById(env, l.key_id);
      const d = first(await goldCall(env, { action: 'device_info', username: l.username, password: l.password }, kk && kk.key));
      if (d.expire && d.expire !== l.expire) {
        await env.DB.prepare('UPDATE gold_lines SET expire=?, updated_at=? WHERE id=?').bind(d.expire, Date.now(), l.id).run();
        await history(env, l.mac, 'sync.expire_changed', { line_id: l.id, expire: d.expire, actor, detail: { from: l.expire } });
      }
      out.push({ mac: l.mac, kind: l.kind, expire: d.expire || l.expire, enabled: d.enabled });
    } catch (e) { out.push({ mac: l.mac, error: String(e.message) }); }
  }
  return { http: 200, synced: out.length, lines: out };
}

// ---- auth helpers ----
async function adminActor(request, env, ctx, roles = ['super_admin']) {
  const auth = request.headers.get('Authorization');
  if (!auth) return null;
  const r = await orig.fetch(new Request('https://internal/api/v1/auth/me', { headers: { Authorization: auth } }), env, ctx);
  if (!r.ok) return null;
  const j = await r.json().catch(() => null);
  return j && j.user && roles.includes(j.user.role) ? j.user : null;
}

// Paid-activation hook decision (pure): admin only, paid plan, flag on.
export function shouldAutoProvision(plan, role, enabled) {
  // La création Strong passe exclusivement par le devis Golden confirmé.
  // Une activation classique de licence ne dépense plus de crédits Strong.
  return false;
}

async function handleGoldAdmin(request, env, ctx, parts) {
  await ensureTables(env);
  const user = await adminActor(request, env, ctx);
  if (!user) return J({ error: 'forbidden', message: 'Admin only' }, request.headers.get('Authorization') ? 403 : 401);
  const actor = user.sub;
  const body = (request.method === 'POST' || request.method === 'PATCH') ? await request.json().catch(() => ({})) : {};
  const url = new URL(request.url);
  const send = (r) => { const { http, ...rest } = r; return J(rest, http || 200); };
  const p = parts[0];
  if (p === 'status' && request.method === 'GET') {
    const cfg = await getConfig(env);
    let reseller = null, err = null;
    const pk = await keyById(env, null);
    try { reseller = pk ? await goldCredits(env, pk.key) : null; if (!pk) err = 'no_gold_key'; } catch (e) { err = String(e.message); }
    const keysInfo = [];
    for (const k of await poolKeys(env, 'trial')) {
      let credits = null, e2 = null;
      try { credits = (await goldCredits(env, k.key)).credits; } catch (e) { e2 = String(e.message).slice(0, 100); }
      keysInfo.push(publicKey(k, { credits, check_error: e2, trials_today: await keyTrialsToday(env, k.id) }));
    }
    const counts = (await env.DB.prepare("SELECT kind, status, COUNT(*) n FROM gold_lines GROUP BY kind, status").all()).results;
    const today = (await env.DB.prepare("SELECT kind, COUNT(*) n FROM gold_lines WHERE created_at >= ? AND status IN ('active','pending') GROUP BY kind").bind(dayStart()).all()).results;
    return J({ ok: !err, keys: keysInfo, key_configured: !!(await getKey(env).catch(() => null)), reseller, error: err, config: cfg, counts, today });
  }
  if (p === 'probe' && request.method === 'GET') {
    const out = [];
    let trace = '';
    try { trace = (await (await fetch('https://www.cloudflare.com/cdn-cgi/trace')).text()).split('\n').filter((l) => /^(ip|colo)=/.test(l)).join(' '); } catch (_) {}
    const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
    for (const base of ['https://cms-8k.net/api/api.php', 'https://8k.online-cms.ru/api/api.php', 'http://8k.online-cms.ru/api/api.php']) {
      for (const ua of [null, UA]) {
        try {
          const qs = new URLSearchParams({ action: 'reseller', api_key: ((await keyById(env, null)) || {}).key || '' });
          const r = await fetch(`${base}?${qs}`, { headers: ua ? { 'user-agent': ua, accept: 'application/json,text/html' } : {} });
          const t = (await r.text()).slice(0, 140).split((await getKey(env)) || '@@').join('***');
          out.push({ base, ua: !!ua, status: r.status, body: t });
        } catch (e) { out.push({ base, ua: !!ua, error: String(e.message) }); }
      }
    }
    const kb = new TextEncoder().encode((await getKey(env)) || ''); const fp = [...new Uint8Array(await crypto.subtle.digest('SHA-256', kb))].slice(0, 4).map((b) => b.toString(16).padStart(2, '0')).join('');
    return J({ egress: trace, key_len: kb.length, key_fp: fp, results: out });
  }
  if ((p === 'key' || p === 'keys') && parts.length === 1 && request.method === 'POST') {
    const k = String(body.key || '').trim();
    if (!/^[A-Za-z0-9]{16,128}$/.test(k)) return J({ error: 'bad_key_format' }, 400);
    const d = first(await goldCall(env, { action: 'reseller' }, k));
    if (!ok(d)) return J({ error: 'key_rejected_by_panel', message: String(d.result || d.message || '').slice(0, 120) }, 400);
    await ensurePool(env);
    const kid = await addKey(env, k, { reseller: d.username, trial_priority: body.trial_priority, use_for_paid: body.use_for_paid,
      trial_cap_per_day: body.trial_cap_per_day, pack: body.pack });
    if (p === 'key') { await storeKey(env, k); _keyCache = null; }
    await audit(env, actor, 'gold.key.add', null, { key_id: kid, reseller: d.username });
    return J({ ok: true, key_id: kid, reseller: d.username, credits: Number(d.credits) });
  }
  if (p === 'keys' && parts.length === 1 && request.method === 'GET') {
    return J({ keys: (await poolKeys(env, 'trial')).map((k) => publicKey(k)),
      disabled: ((await env.DB.prepare('SELECT * FROM gold_keys WHERE enabled=0').all()).results || []).map((k) => publicKey(k)) });
  }
  if (p === 'keys' && parts.length === 2 && (request.method === 'PATCH' || request.method === 'POST')) {
    await ensurePool(env);
    const r = await env.DB.prepare('SELECT * FROM gold_keys WHERE id=?').bind(parts[1]).first();
    if (!r) return J({ error: 'not_found' }, 404);
    const f = {};
    if (body.trial_priority != null) f.trial_priority = Number(body.trial_priority) | 0;
    if (body.use_for_paid != null) f.use_for_paid = body.use_for_paid ? 1 : 0;
    if (body.enabled != null) f.enabled = body.enabled ? 1 : 0;
    if ('trial_cap_per_day' in body) f.trial_cap_per_day = body.trial_cap_per_day == null ? null : Number(body.trial_cap_per_day) | 0;
    if ('pack' in body) { if (body.pack != null && !/^(all|\d+(,\d+)*)$/.test(String(body.pack))) return J({ error: 'bad_pack' }, 400); f.pack = body.pack == null ? null : String(body.pack); }
    for (const [c, v] of Object.entries(f)) await env.DB.prepare(`UPDATE gold_keys SET ${c}=? WHERE id=?`).bind(v, r.id).run();
    await audit(env, actor, 'gold.key.update', null, { key_id: r.id, ...f });
    return J({ ok: true, key: publicKey(await env.DB.prepare('SELECT * FROM gold_keys WHERE id=?').bind(r.id).first()) });
  }
  if (p === 'keys' && parts.length === 2 && request.method === 'DELETE') {
    await ensurePool(env);
    const inUse = (await env.DB.prepare("SELECT COUNT(*) n FROM gold_lines WHERE key_id=? AND status='active'").bind(parts[1]).first()).n;
    // keep the row if lines depend on it (renew/sync need it): disable instead of delete
    if (inUse) await env.DB.prepare('UPDATE gold_keys SET enabled=0 WHERE id=?').bind(parts[1]).run();
    else await env.DB.prepare('DELETE FROM gold_keys WHERE id=?').bind(parts[1]).run();
    await audit(env, actor, 'gold.key.remove', null, { key_id: parts[1], disabled_only: !!inUse });
    return J({ ok: true, removed: !inUse, disabled: !!inUse });
  }
  if (p === 'bouquets' && request.method === 'GET') { const k = await keyById(env, url.searchParams.get('key_id')); return J(await goldCall(env, { action: 'bouquet' }, k && k.key)); }
  if (p === 'config' && request.method === 'POST') {
    if (Object.keys(body || {}).some(k => ['gold_trial_enabled','gold_trial_sub','gold_trial_max_per_day'].includes(k))) {
      return J({ error: 'trial_control_required', message: 'Utilisez la page Essais gratuits 24 h. Le contrat démo doit être vérifié avant activation.' }, 409);
    }
    const changed = {};
    for (const [k, v] of Object.entries(body || {})) {
      if (!CONFIG_KEYS.includes(k)) return J({ error: 'bad_key', key: k }, 400);
      const s = String(v);
      if (/enabled$/.test(k) && !['0', '1'].includes(s)) return J({ error: 'bad_value', key: k }, 400);
      if (k !== 'gold_pack' && !/^\d+$/.test(s)) return J({ error: 'bad_value', key: k }, 400);
      if (k === 'gold_pack' && !/^(all|\d+(,\d+)*)$/.test(s)) return J({ error: 'bad_value', key: k }, 400);
      if (k === 'gold_trial_sub' && ['1', '3', '6', '12'].includes(s)) return J({ error: 'trial_sub_would_spend_credits' }, 400);
      changed[k] = s;
    }
    for (const [k, v] of Object.entries(changed)) {
      await env.DB.prepare('INSERT INTO app_config (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value').bind(k, v).run();
    }
    await audit(env, actor, 'gold.config', null, changed);
    return J({ ok: true, config: await getConfig(env) });
  }
  if (p === 'provision' && request.method === 'POST') {
    const kind = body.demo === true ? 'demo' : 'paid';
    if (kind === 'paid' && body.dry_run !== true) return J({error:'golden_confirmation_required',
      message:'Utilisez Golden et confirmez son devis avant de créer une ligne.'},409);
    return send(await provision(env, ctx, { kind, mac: body.mac, sub: body.sub, actor, dryRun: body.dry_run === true }));
  }
  if (p === 'renew' && request.method === 'POST') return send(await renew(env, ctx, body.mac, body.sub, actor));
  if (p === 'sync' && request.method === 'POST') return send(await sync(env, actor));
  if (p === 'hook-check' && request.method === 'POST') {
    const cfg = await getConfig(env);
    return J({ plan: body.plan, role: body.role, gold_enabled: body.gold_enabled ?? cfg.gold_enabled,
      would_provision: shouldAutoProvision(body.plan, body.role, String(body.gold_enabled ?? cfg.gold_enabled)) });
  }
  if ((p === 'history' || p === 'lines') && request.method === 'GET') {
    const q = url.searchParams.get('mac');
    if (q) {
      const mac = normMac(q);
      if (!mac) return J({ error: 'bad_mac' }, 400);
      const lines = (await env.DB.prepare('SELECT * FROM gold_lines WHERE mac=? ORDER BY created_at').bind(mac).all()).results.map(publicLine);
      const events = (await env.DB.prepare('SELECT * FROM gold_history WHERE mac=? ORDER BY created_at DESC LIMIT 200').bind(mac).all()).results
        .map((e) => ({ ...e, detail: e.detail_json ? JSON.parse(e.detail_json) : null, detail_json: undefined }));
      const trial = lines.find((l) => l.kind === 'trial');
      return J({ mac, trial_used: !!(trial && trial.status === 'active'), lines, history: events });
    }
    const limit = Math.min(200, Number(url.searchParams.get('limit')) || 50);
    const rows = (await env.DB.prepare('SELECT * FROM gold_lines ORDER BY created_at DESC LIMIT ?').bind(limit).all()).results.map(publicLine);
    return J({ lines: rows });
  }
  return J({ error: 'not_found' }, 404);
}

// Le nouveau routeur vérifie l'identité, le registre global et la reprise.
const trialRuntime = createTrialRuntime({ authenticate: adminActor, sealSource: goldSealSource,
  openSourceList: goldOpenSourceList, notifyBox: goldNotifyBox });

// Paid activation hook: runs after the original /api/v1/activate succeeded.
async function afterActivate(env, ctx, request, reqBody, resp) {
  let mac, trace;
  const progress = (stage, orderId = null) => history(env, mac, 'activation.delivery', {
    detail: { trace_id: trace, stage, order_id: orderId }, actor: 'system',
  });
  try {
    await ensureTables(env);
    const out = await resp.clone().json().catch(() => null);
    if (!out || !out.ok || !out.mac) return;
    mac = normMac(out.mac);
    trace = out.trace_id || resp.headers.get('X-Request-Id') || request.headers.get('X-Request-Id');
    const user = await adminActor(request, env, ctx);
    const cfg = await getConfig(env);
    await history(env, mac, 'activation', { actor: user ? user.sub : 'reseller', detail: { plan: out.plan, expires_at: out.expires_at, license_id: out.license_id, credits_charged: out.credits_charged } });
    if (!shouldAutoProvision(out.plan, user && user.role, cfg.gold_enabled)) { await progress('skipped'); return; }
    await progress('preparing');
    const existing = await env.DB.prepare("SELECT id FROM gold_lines WHERE mac=? AND kind='paid' AND status='active'").bind(mac).first();
    if (existing) {
      const r = await renew(env, ctx, mac, 12, user.sub);
      await audit(env, user.sub, 'gold.hook.renew', mac, r);
      await progress(r.renewed ? 'renewed' : 'failed');
      return;
    }
    const r = await provision(env, ctx, { kind: 'paid', mac, sub: 12, actor: user.sub, traceId: trace });
    await audit(env, user.sub, 'gold.hook.provision', mac, { http: r.http, error: r.error, created: r.created });
    await progress(r.delivery?.ok ? 'source_saved' : 'failed', r.delivery?.order_id);
  } catch {
    if (mac && trace) await progress('failed');
    console.log('gold.hook_failed');
  }
}

// CORS explicite pour le panel existant et les en-têtes des deux applications.
const allowedOrigins = new Set(['https://atlas-console-k7q2.vercel.app',
  'https://tvking-admin.pages.dev','https://admin.7themotion.com',
  'http://localhost:5173','http://127.0.0.1:5173']);
function cors(request,env,response) {
  const headers = new Headers(response.headers), origin=request.headers.get('Origin');
  headers.delete('Access-Control-Allow-Origin');
  if (origin && (allowedOrigins.has(origin) || String(env.PANEL_ORIGINS||'').split(',').map(x=>x.trim()).includes(origin))) {
    headers.set('Access-Control-Allow-Origin',origin);
    headers.append('Vary','Origin');
  }
  headers.set('Access-Control-Allow-Methods','GET, POST, PUT, PATCH, DELETE, OPTIONS');
  headers.set('Access-Control-Allow-Headers','Authorization, Content-Type, X-Device-Secret, X-App-Brand, X-App-Version, X-Request-Id, X-Client-Sent-At, Idempotency-Key');
  headers.set('Cache-Control','no-store');
  return new Response(response.body,{status:response.status,headers});
}

const realtimeRoutes = createRealtimeRoutes({ original: orig, actorFor: adminActor });
const goldenRoutes = createGoldenRoutes({
  authenticate: adminActor,
  config: async env => {
    const cfg=await getConfig(env);
    // Aucun prix par défaut supposé pour un achat : le tarif doit avoir été
    // renseigné explicitement par l'administrateur dans la configuration.
    const tariff=await env.DB.prepare("SELECT value FROM app_config WHERE key='gold_cost_per_month'").first();
    return {...cfg,gold_cost_per_month:tariff?.value??''};
  },
  keys: env => poolKeys(env,'paid'),
  balance: async (env,key) => {
    const data=first(await goldCall(env,{action:'reseller'},key.key,8000));
    const credits=Number(data.credits);
    if (!ok(data)||data.credits==null||!Number.isFinite(credits)||credits<0) throw new Error('gold_balance_unavailable');
    return credits;
  },
  templates: async (env,key) => goldenTemplates(await goldCall(env,{action:'bouquet'},key.key,8000)),
  create: async (env,key,order) => {
    const data=first(await goldCall(env,{action:'new',type:'m3u',sub:String(order.sub),
      pack:order.bouquet,note:`Golden ${order.id} ${order.mac}`},key.key));
    const credentials=ok(data)?parseLineUrl(data.url):null;
    if (!credentials||!['http:','https:'].includes(new URL(credentials.server_url).protocol))
      throw new Error('gold_creation_uncertain');
    // Réutiliser l'URL M3U fournie par Strong telle quelle : aucune URL de
    // catalogue inventée et un seul téléchargement pour l'import initial.
    return {user_id:data.user_id,credentials:{m3u_url:String(data.url)}};
  },
  seal: async (env,credentials) => {
    const source={type:'m3u',label:'Golden',origin:'panel',...credentials};
    const sealed=await goldSealSource(env,source);
    if (!sealed.m3u_url?.startsWith('enc1.')||sealed.m3u_url===credentials.m3u_url) throw new Error('gold_encryption_unavailable');
    return sealed;
  },
  deliver: createGoldenDelivery({original:orig,tokenFor:internalAdminToken,notifyBox:goldNotifyBox}),
});

export default {
  ...orig,
  async fetch(request, rawEnv, ctx) {
    // Tous les lecteurs utilisent la même clé que le canal source existant.
    const env=sourceEncryptionEnv({...rawEnv,PANEL_ORIGINS:
      [rawEnv.PANEL_ORIGINS,'https://atlas-console-k7q2.vercel.app'].filter(Boolean).join(',')});
    const p=new URL(request.url).pathname;
    const own=p.startsWith('/api/v1/gold/') || p.startsWith('/api/gold-trial') ||
      p==='/api/v1/device/trial' || p==='/api/device-proof' || p==='/api/v1/activation-delivery' ||
      p.startsWith('/api/v1/rt/') || p==='/api/v1/boxes/live' || p==='/api/v1/online' || p.startsWith('/api/box/');
    if (own && request.method==='OPTIONS') return cors(request,env,new Response(null,{status:204}));
    try {
      const goldenProtected=await protectGoldenSource(request,env);
      if (goldenProtected) return cors(request,env,goldenProtected);
      if (p.startsWith('/api/v1/gold/golden')) {
        // Même point d'entrée Gold et même authentification de production.
        await ensureTables(env);
        return cors(request,env,await goldenRoutes(request,env,ctx));
      }
      const realtime = await realtimeRoutes(request, env, ctx);
      if (realtime) return realtime.status === 101 ? realtime : cors(request, env, realtime);
      if (/^\/api\/v1\/licenses(?:\/[^/]+(?:\/renew)?)?$/.test(p) && ['POST','PATCH'].includes(request.method)) {
        const response=await orig.fetch(request,env,ctx);
        if (response.ok) {
          const id=p.split('/')[4] || (await response.clone().json()).id;
          const device=await env.DB.prepare(`SELECT d.mac FROM licenses l JOIN devices d ON d.id=l.device_id WHERE l.id=?`).bind(id).first();
          if (device) ctx.waitUntil(goldNotifyBox(env,device.mac,'license'));
        }
        return response;
      }
      const settingKind=globalPanelChange(p);
      if (settingKind && ['POST','PATCH','PUT','DELETE'].includes(request.method)) {
        const response = await orig.fetch(request, env, ctx);
        if (response.ok) ctx.waitUntil(pushPanelSettingChange(env,settingKind));
        return response;
      }
      if (p==='/api/v1/activation-delivery' && request.method==='GET') {
        const actor=await adminActor(request,env,ctx,['super_admin','admin','reseller']);
        if (!actor) return cors(request,env,J({error:'unauthorized'},401));
        const url=new URL(request.url), mac=normMac(url.searchParams.get('mac'));
        const trace=url.searchParams.get('trace')||'';
        if (!mac || !/^[A-Za-z0-9_.:-]{8,80}$/.test(trace)) return cors(request,env,J({error:'bad_query'},400));
        if (actor.role==='reseller') {
          const device=await env.DB.prepare('SELECT reseller_id FROM devices WHERE mac=?').bind(mac).first();
          if (!device || device.reseller_id!==(actor.sub||actor.id)) return cors(request,env,J({error:'forbidden'},403));
        }
        return cors(request,env,J(await activationDeliveryState(env,mac,trace)));
      }
      const routed=await trialRuntime(request,env,ctx);
      if (routed) return cors(request,env,routed);
      if (p.startsWith('/api/v1/gold/')) {
        const parts=p.slice('/api/v1/gold/'.length).split('/').filter(Boolean);
        return cors(request,env,await handleGoldAdmin(request,env,ctx,parts));
      }
      if (p==='/api/v1/activate' && request.method==='POST') {
        const raw=await request.text(), fwd=new Request(request,{body:raw});
        const resp=await orig.fetch(fwd,env,ctx);
        if (resp.ok) ctx.waitUntil(afterActivate(env,ctx,request,raw,resp.clone()));
        if (resp.ok) {
          // Les réponses « déjà à vie » n'avaient pas trace_id dans le JSON.
          // On expose seulement l'identifiant de suivi, jamais le JWT interne.
          const body=await resp.clone().json().catch(()=>null);
          if (body && !body.trace_id && resp.headers.get('X-Request-Id')) {
            const headers=new Headers(resp.headers);headers.delete('Content-Length');
            return new Response(JSON.stringify({...body,trace_id:resp.headers.get('X-Request-Id')}),{status:resp.status,headers});
          }
        }
        return resp;
      }
    } catch {
      // Ni URL, ni réponse fournisseur, ni exception brute dans l'interface.
      return cors(request,env,J({error:'unavailable',message:'Service indisponible pour le moment. Réessayez plus tard.'},503));
    }
    return orig.fetch(request,env,ctx);
  },
};
