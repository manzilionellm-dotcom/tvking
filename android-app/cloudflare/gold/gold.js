// 7 MOTION x GOLD/Strong panel (cms-8k.net API v1.81) — wrapper module.
// Main module: wraps the unchanged production bundle (./worker.js).
import orig from './worker.js';
export * from './worker.js';

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

async function goldCall(env, params, keyOverride) {
  const key = keyOverride || await getKey(env);
  if (!key) throw new Error('gold_key_missing');
  const qs = new URLSearchParams({ ...params, api_key: key });
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 45000);
  try {
    const r = await fetch(`${GOLD_BASE}?${qs}`, { signal: ctl.signal, headers: { accept: 'application/json' } });
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

async function deliverToDevice(env, ctx, mac, creds, label) {
  const token = await internalAdminToken(env);
  const auth = { Authorization: `Bearer ${token}`, 'content-type': 'application/json' };
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
  const delivery = await deliverToDevice(env, ctx, mac, creds, kind === 'paid' ? '7 MOTION' : '7 MOTION Essai').catch((e) => ({ ok: false, error: String(e.message) }));
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
async function adminActor(request, env, ctx) {
  const auth = request.headers.get('Authorization');
  if (!auth) return null;
  const r = await orig.fetch(new Request('https://internal/api/v1/auth/me', { headers: { Authorization: auth } }), env, ctx);
  if (!r.ok) return null;
  const j = await r.json().catch(() => null);
  return j && j.user && j.user.role === 'super_admin' ? j.user : null;
}

// Paid-activation hook decision (pure): admin only, paid plan, flag on.
export function shouldAutoProvision(plan, role, enabled) {
  if (enabled !== '1' || role !== 'super_admin') return false;
  if (typeof plan !== 'string' || plan.startsWith('trial')) return false;
  return plan === 'yearly' || plan === 'lifetime';
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

// Device "Je teste" button. Device auth = MAC must be a known device (heartbeat-registered),
// android_id must match the trial anchor when one exists, per-IP rate limit, 1 trial per MAC forever.
const _ipHits = new Map();
async function handleDeviceTrial(request, env, ctx) {
  await ensureTables(env);
  if (request.method !== 'POST') return J({ error: 'method' }, 405);
  const ip = request.headers.get('CF-Connecting-IP') || '';
  const k = ip + ':' + Math.floor(Date.now() / 60000);
  const hits = (_ipHits.get(k) || 0) + 1; _ipHits.set(k, hits);
  if (_ipHits.size > 5000) _ipHits.clear();
  if (hits > 5) return J({ error: 'rate_limited' }, 429);
  const body = await request.json().catch(() => ({}));
  const mac = normMac(body.mac);
  if (!mac) return J({ error: 'bad_mac' }, 400);
  const appVersion = String(body.app_version || request.headers.get('X-App-Version') || '').slice(0, 40) || null;
  const androidId = String(body.android_id || '').slice(0, 64) || null;
  const dev = (await env.DB.prepare('SELECT mac FROM devices WHERE mac = ?').bind(mac).first().catch(() => null))
    || (await env.DB.prepare('SELECT mac FROM trial_anchors WHERE mac = ?').bind(mac).first().catch(() => null));
  if (!dev) {
    await history(env, mac, 'trial.refused', { ip, app_version: appVersion, actor: 'device', detail: { reason: 'unknown_device' } });
    return J({ error: 'unknown_device', message: 'Ouvre l’app une fois connectée à Internet puis réessaie.' }, 403);
  }
  try {
    const anchor = await env.DB.prepare('SELECT android_id FROM trial_anchors WHERE mac = ?').bind(mac).first();
    if (anchor && anchor.android_id && androidId && anchor.android_id !== androidId) {
      await history(env, mac, 'trial.refused', { ip, app_version: appVersion, actor: 'device', detail: { reason: 'device_mismatch' } });
      return J({ error: 'device_mismatch' }, 403);
    }
  } catch (_) {}
  // paid customers do not need a trial
  const paid = await env.DB.prepare("SELECT 1 FROM gold_lines WHERE mac=? AND kind='paid' AND status='active'").bind(mac).first();
  if (paid) return J({ error: 'already_customer' }, 409);
  const r = await provision(env, ctx, { kind: 'trial', mac, actor: 'device:' + mac, ip, appVersion, androidId });
  const msg = {
    trial_disabled: 'Les essais sont fermés pour le moment.', trial_already_used: 'Essai déjà utilisé sur cet appareil.',
    daily_cap_reached: 'Trop de demandes aujourd’hui, réessaie demain.', in_progress: 'Activation en cours…',
  };
  if (r.created) return J({ ok: true, mac, expire: r.expire, delivered: !!(r.delivery && r.delivery.ok), message: 'Essai activé ! Ta liste arrive dans quelques secondes.' }, 201);
  return J({ ok: false, error: r.error || 'unavailable', message: msg[r.error] || 'Essai indisponible pour le moment.' }, r.http && r.http >= 400 ? r.http : 409);
}

// Paid activation hook: runs after the original /api/v1/activate succeeded.
async function afterActivate(env, ctx, request, reqBody, resp) {
  try {
    await ensureTables(env);
    const out = await resp.clone().json().catch(() => null);
    if (!out || !out.ok || !out.mac) return;
    const mac = normMac(out.mac);
    const user = await adminActor(request, env, ctx);
    const cfg = await getConfig(env);
    await history(env, mac, 'activation', { actor: user ? user.sub : 'reseller', detail: { plan: out.plan, expires_at: out.expires_at, license_id: out.license_id, credits_charged: out.credits_charged } });
    if (!shouldAutoProvision(out.plan, user && user.role, cfg.gold_enabled)) return;
    const existing = await env.DB.prepare("SELECT id FROM gold_lines WHERE mac=? AND kind='paid' AND status='active'").bind(mac).first();
    if (existing) { const r = await renew(env, ctx, mac, 12, user.sub); await audit(env, user.sub, 'gold.hook.renew', mac, r); return; }
    const r = await provision(env, ctx, { kind: 'paid', mac, sub: 12, actor: user.sub });
    await audit(env, user.sub, 'gold.hook.provision', mac, { http: r.http, error: r.error, created: r.created });
  } catch (e) { console.log('gold.hook_failed', String(e && e.message)); }
}

export default {
  ...orig,
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const p = url.pathname;
    if (p.startsWith('/api/v1/gold/')) {
      const parts = p.slice('/api/v1/gold/'.length).split('/').filter(Boolean);
      try { return await handleGoldAdmin(request, env, ctx, parts); }
      catch (e) { return J({ error: 'gold_internal', message: String(e && e.message) }, 500); }
    }
    if (p === '/api/gold-trial' || p === '/api/v1/device/trial') {
      try { return await handleDeviceTrial(request, env, ctx); }
      catch (e) { return J({ error: 'gold_internal' }, 500); }
    }
    if (p === '/api/v1/activate' && request.method === 'POST') {
      const raw = await request.text();
      const fwd = new Request(request, { body: raw });
      const resp = await orig.fetch(fwd, env, ctx);
      if (resp.ok) ctx.waitUntil(afterActivate(env, ctx, request, raw, resp.clone()));
      return resp;
    }
    return orig.fetch(request, env, ctx);
  },
};