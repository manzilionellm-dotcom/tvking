// Account security primitives: no provider calls, no secrets in logs or URLs.
const enc = new TextEncoder();
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const schemas = new WeakSet();
export function constantEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}
export function strongPassword(s) { return typeof s === 'string' && s.length >= 12 && s.length <= 256 && /[a-z]/.test(s) && /[A-Z]/.test(s) && /[0-9]/.test(s); }
export async function digest(s) { return [...new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(s)))].map(b => b.toString(16).padStart(2, '0')).join(''); }
function randomHex(n = 32) { return [...crypto.getRandomValues(new Uint8Array(n))].map(b => b.toString(16).padStart(2, '0')).join(''); }
function actorKey(user) { return (user.role === 'reseller' ? 'reseller:' : 'admin:') + user.sub; }
export async function securitySchema(env) {
  if (schemas.has(env.DB)) return;
  await env.DB.batch([
    env.DB.prepare('CREATE TABLE IF NOT EXISTS auth_sessions (id TEXT PRIMARY KEY, actor TEXT NOT NULL, refresh_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL)'),
    env.DB.prepare('CREATE TABLE IF NOT EXISTS auth_factors (actor TEXT PRIMARY KEY, secret TEXT, enabled INTEGER NOT NULL DEFAULT 0, pending TEXT, pending_until INTEGER, last_counter INTEGER NOT NULL DEFAULT -1)'),
    env.DB.prepare('CREATE TABLE IF NOT EXISTS auth_recovery (actor TEXT NOT NULL, code_hash TEXT NOT NULL, PRIMARY KEY(actor, code_hash))'),
    env.DB.prepare('CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_refresh ON auth_sessions(refresh_hash)'),
    env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_auth_actor ON auth_sessions(actor)'),
  ]);
  schemas.add(env.DB);
}
const COOKIE = '__Host-atlas-refresh';
export function sessionCookie(refresh, age = 7 * 86400) { return `${COOKIE}=${refresh}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=${age}`; }
function cookie(request) { return (request.headers.get('Cookie') || '').split(';').map(s => s.trim()).find(s => s.startsWith(COOKIE + '='))?.slice(COOKIE.length + 1) || ''; }
export async function createSession(env, user, now = Date.now()) {
  await securitySchema(env);
  const sid = crypto.randomUUID(), refresh = randomHex();
  await env.DB.prepare('INSERT INTO auth_sessions (id, actor, refresh_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)').bind(sid, actorKey(user), await digest(refresh), now + 7 * 86400000, now).run();
  return { sid, refresh };
}
export async function sessionValid(env, claims) {
  // Legacy JWTs have no sid; accept only until their original expiration.
  // Password rotation invalidates those via the existing password epoch.
  if (!claims.sid) return true;
  await securitySchema(env);
  const row = await env.DB.prepare('SELECT actor, expires_at FROM auth_sessions WHERE id = ?').bind(claims.sid).first();
  return !!row && row.actor === actorKey(claims) && row.expires_at > Date.now();
}
export async function refreshSession(env, request) {
  await securitySchema(env);
  const raw = cookie(request);
  if (!/^[a-f0-9]{64}$/.test(raw)) return null;
  const hash = await digest(raw);
  const row = await env.DB.prepare('SELECT * FROM auth_sessions WHERE refresh_hash = ? AND expires_at > ?').bind(hash, Date.now()).first();
  if (!row) return null;
  const next = randomHex();
  const result = await env.DB.prepare('UPDATE auth_sessions SET refresh_hash = ? WHERE id = ? AND refresh_hash = ?').bind(await digest(next), row.id, hash).run();
  if (!result.meta?.changes) return null; // concurrent/replayed refresh denied
  const split = row.actor.indexOf(':');
  return { sub: row.actor.slice(split + 1), role: row.actor.slice(0, split) === 'reseller' ? 'reseller' : 'admin', sid: row.id, refresh: next };
}
export async function revokeSessions(env, user, except = null) {
  await securitySchema(env);
  await env.DB.prepare('DELETE FROM auth_sessions WHERE actor = ? AND id != ?').bind(actorKey(user), except || '').run();
}
export async function revokeSession(env, sid) {
  if (!sid) return;
  await env.DB.prepare('DELETE FROM auth_sessions WHERE id = ?').bind(sid).run();
}
function base32(bytes) {
  let bits = 0, value = 0, out = '';
  for (const b of bytes) { value = (value << 8) | b; bits += 8; while (bits >= 5) { out += B32[(value >>> (bits - 5)) & 31]; bits -= 5; } }
  if (bits) out += B32[(value << (5 - bits)) & 31]; return out;
}
function decode32(s) {
  let bits = 0, value = 0; const bytes = [];
  for (const c of s.replace(/=+$/, '').toUpperCase()) { const n = B32.indexOf(c); if (n < 0) throw new Error('bad_base32'); value = (value << 5) | n; bits += 5; if (bits >= 8) { bytes.push((value >>> (bits - 8)) & 255); bits -= 8; } }
  return new Uint8Array(bytes);
}
export async function totp(secret, counter) {
  const buffer = new ArrayBuffer(8); new DataView(buffer).setBigUint64(0, BigInt(counter));
  const key = await crypto.subtle.importKey('raw', decode32(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, buffer)); const o = bytes[19] & 15;
  const n = ((bytes[o] & 127) << 24) | (bytes[o+1] << 16) | (bytes[o+2] << 8) | bytes[o+3];
  return (n % 1000000).toString().padStart(6, '0');
}
async function encryptionKey(env) {
  const raw = env.ACCOUNT_ENCRYPTION_KEY || env.ADMIN_SECRET;
  if (!raw || raw.length < 32) throw new Error('security_unconfigured');
  return crypto.subtle.importKey('raw', await crypto.subtle.digest('SHA-256', enc.encode('atlas-totp-v1:' + raw)), 'AES-GCM', false, ['encrypt','decrypt']);
}
async function seal(env, text) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const bytes = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await encryptionKey(env), enc.encode(text)));
  return btoa(String.fromCharCode(...iv, ...bytes));
}
async function open(env, value) {
  const bytes = Uint8Array.from(atob(value), c => c.charCodeAt(0));
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, await encryptionKey(env), bytes.slice(12)));
}
export async function factorStatus(env, user) {
  await securitySchema(env); const row = await env.DB.prepare('SELECT enabled FROM auth_factors WHERE actor = ?').bind(actorKey(user)).first(); return { enabled: row?.enabled === 1 };
}
export async function startFactor(env, user) {
  await securitySchema(env); const actor = actorKey(user);
  if ((await factorStatus(env, user)).enabled) return null;
  const secret = base32(crypto.getRandomValues(new Uint8Array(20)));
  await env.DB.prepare('INSERT INTO auth_factors (actor, pending, pending_until) VALUES (?, ?, ?) ON CONFLICT(actor) DO UPDATE SET pending=excluded.pending, pending_until=excluded.pending_until').bind(actor, await seal(env, secret), Date.now() + 600000).run();
  return { secret, uri: `otpauth://totp/${encodeURIComponent('Atlas:' + user.email)}?secret=${secret}&issuer=Atlas&algorithm=SHA1&digits=6&period=30` };
}
async function codeCounter(secret, code, last = -1, now = Date.now()) {
  if (!/^[0-9]{6}$/.test(String(code))) return null;
  const current = Math.floor(now / 30000);
  for (const counter of [current, current - 1, current + 1]) { if (counter > last && constantEqual(await totp(secret, counter), String(code))) return counter; }
  return null;
}
export async function confirmFactor(env, user, code) {
  await securitySchema(env); const actor = actorKey(user);
  const row = await env.DB.prepare('SELECT * FROM auth_factors WHERE actor = ?').bind(actor).first();
  if (!row?.pending || row.enabled || row.pending_until <= Date.now()) return null;
  const counter = await codeCounter(await open(env, row.pending), code);
  if (counter === null) return null;
  const recovery = Array.from({length: 10}, () => randomHex(8));
  const result = await env.DB.batch([
    env.DB.prepare('UPDATE auth_factors SET secret=pending, enabled=1, pending=NULL, pending_until=NULL, last_counter=? WHERE actor=? AND enabled=0 AND pending=?').bind(counter, actor, row.pending),
    ...await Promise.all(recovery.map(async c => env.DB.prepare('INSERT OR IGNORE INTO auth_recovery (actor, code_hash) SELECT ?, ? WHERE changes() = 1').bind(actor, await digest(c)))),
  ]);
  return result[0].meta?.changes ? recovery : null;
}
export async function verifyFactor(env, user, code, recovery = false) {
  if (recovery && typeof code === 'string') code = code.trim().toLowerCase();
  await securitySchema(env); const actor = actorKey(user);
  const row = await env.DB.prepare('SELECT * FROM auth_factors WHERE actor = ?').bind(actor).first();
  if (!row?.enabled) return true;
  if (recovery && /^[a-f0-9]{16}$/.test(String(code))) {
    const result = await env.DB.prepare('DELETE FROM auth_recovery WHERE actor=? AND code_hash=?').bind(actor, await digest(code)).run();
    return !!result.meta?.changes;
  }
  const counter = await codeCounter(await open(env, row.secret), code, row.last_counter);
  if (counter === null) return false;
  const result = await env.DB.prepare('UPDATE auth_factors SET last_counter=? WHERE actor=? AND last_counter < ?').bind(counter, actor, counter).run();
  return !!result.meta?.changes;
}
export async function disableFactor(env, user) {
  const actor = actorKey(user);
  await env.DB.batch([env.DB.prepare('DELETE FROM auth_factors WHERE actor=?').bind(actor), env.DB.prepare('DELETE FROM auth_recovery WHERE actor=?').bind(actor)]);
}
export function validateWriteBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return false;
  const strings = new Set(['mac','email','username','password','current_password','new_password','name','title','label','code','url','server_url','description']);
  function valid(v, depth) {
    if (depth > 12) return false;
    if (typeof v === 'string') return v.length <= 65536;
    if (typeof v === 'number') return Number.isFinite(v);
    if (!v || typeof v !== 'object') return true;
    const entries = Object.entries(v); if (entries.length > 1000) return false;
    return entries.every(([k, val]) => !['__proto__','prototype','constructor'].includes(k) && (!strings.has(k) || val == null || typeof val === 'string') && valid(val, depth+1));
  }
  return valid(body, 0);
}
