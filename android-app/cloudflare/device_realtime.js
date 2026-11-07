import { constantEqual } from './account_security.js';
// Device sessions are separate from panel JWTs. No credential ever travels
// in a WS URL: only a short-lived, single-use opaque ticket does.
const MAC = /^MK(?::[0-9A-F]{2}){5}$/;
const TTL = 3600_000;
export const DEVICE_HUB = 'devices-v1';
const enc = new TextEncoder();
function b64(bytes) { return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function unb64(text) { return Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)); }
async function key(env) {
  if (!env.DEVICE_TOKEN_SECRET || env.DEVICE_TOKEN_SECRET.length < 32) return null;
  return crypto.subtle.importKey('raw', enc.encode('atlas-device-v1:' + env.DEVICE_TOKEN_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}
export async function licenseBinding(env, mac) {
  if (!env.DB || !MAC.test(mac)) return null;
  const dev = await env.DB.prepare('SELECT id FROM devices WHERE mac = ?').bind(mac).first();
  if (!dev) return null;
  const lic = await env.DB.prepare('SELECT id FROM licenses WHERE device_id = ? ORDER BY (expires_at IS NULL) DESC, expires_at DESC, id DESC LIMIT 1').bind(dev.id).first();
  return { device: String(dev.id), license: lic ? String(lic.id) : 'trial' };
}
export async function signDeviceToken(env, mac, binding, now = Date.now()) {
  const k = await key(env);
  if (!k || !MAC.test(mac) || !binding) return null;
  const payload = b64(enc.encode(JSON.stringify({ aud: 'atlas-device', mac, ...binding, exp: now + TTL })));
  const sig = await crypto.subtle.sign('HMAC', k, enc.encode(payload));
  return payload + '.' + b64(new Uint8Array(sig));
}
export async function verifyDeviceToken(env, token, now = Date.now()) {
  try {
    if (typeof token !== 'string' || token.length > 2048) return null;
    const parts = token.split('.');
    if (parts.length !== 2) return null;
    const k = await key(env);
    if (!k || !await crypto.subtle.verify('HMAC', k, unb64(parts[1]), enc.encode(parts[0]))) return null;
    const p = JSON.parse(new TextDecoder().decode(unb64(parts[0])));
    if (p.aud !== 'atlas-device' || !MAC.test(p.mac) || !Number.isFinite(p.exp) || p.exp <= now || p.exp > now + TTL) return null;
    const binding = await licenseBinding(env, p.mac);
    return binding && binding.device === p.device && binding.license === p.license ? p : null;
  } catch { return null; }
}

// TOFU migration: a new installation supplies a random KeyStore-protected
// key. An existing device may enrol only with its already recorded Android ID.
// Never issue a token to a MAC-only request. Existing legacy HTTP endpoints
// remain compatible; this does NOT retrofit their historical authentication.
export async function attachDeviceToken(env, mac, status, request, { created = false, previousAndroidId = null } = {}) {
  if (!status?.exists || !env.DB || !await key(env)) return status;
  const deviceKey = request.headers.get('X-Device-Key') || '';
  if (!/^[a-f0-9]{64}$/.test(deviceKey)) return status;
  await env.DB.prepare('CREATE TABLE IF NOT EXISTS device_session_keys (mac TEXT PRIMARY KEY, key_hash TEXT NOT NULL)').run();
  const digest = b64(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(deviceKey))));
  let row = await env.DB.prepare('SELECT key_hash FROM device_session_keys WHERE mac = ?').bind(mac).first();
  if (!row) {
    const suppliedId = request.headers.get('X-Device-Id') || '';
    if (previousAndroidId === null) {
      const dev = await env.DB.prepare('SELECT android_id FROM devices WHERE mac = ?').bind(mac).first();
      previousAndroidId = dev?.android_id || '';
    }
    if (!created && (!suppliedId || !previousAndroidId || !constantEqual(suppliedId, previousAndroidId))) return status;
    await env.DB.prepare('INSERT OR IGNORE INTO device_session_keys (mac, key_hash) VALUES (?, ?)').bind(mac, digest).run();
    row = await env.DB.prepare('SELECT key_hash FROM device_session_keys WHERE mac = ?').bind(mac).first();
  }
  if (!constantEqual(row?.key_hash, digest)) return status;
  const token = await signDeviceToken(env, mac, await licenseBinding(env, mac));
  return token ? { ...status, device_token: token } : status;
}
export function hub(env) { return env.RT_HUB?.get(env.RT_HUB.idFromName(DEVICE_HUB)); }
function json(data, status = 200) { return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } }); }
export async function deviceRealtimeRoute(request, env) {
  const url = new URL(request.url);
  if (url.pathname === '/api/device-rt/ticket' && request.method === 'POST') {
    const session = await verifyDeviceToken(env, (request.headers.get('Authorization') || '').replace(/^Bearer /, ''));
    if (!session) return json({ error: 'device_auth_required' }, 401);
    const target = hub(env);
    if (!target || String(env.REALTIME_PUSH_OFF) === '1') return json({ error: 'realtime_unavailable' }, 503);
    return target.fetch('https://hub/device-ticket', { method: 'POST', body: JSON.stringify({ mac: session.mac, exp: session.exp }) });
  }
  if (url.pathname === '/api/device-rt/ws' && request.method === 'GET') {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') return json({ error: 'upgrade_required' }, 426);
    const ticket = url.searchParams.get('ticket') || '';
    if (!/^[a-f0-9-]{36}$/.test(ticket)) return json({ error: 'invalid_ticket' }, 401);
    const target = hub(env);
    if (!target || String(env.REALTIME_PUSH_OFF) === '1') return json({ error: 'realtime_unavailable' }, 503);
    return target.fetch(new Request('https://hub/device-ws?ticket=' + ticket, { headers: { Upgrade: 'websocket' } }));
  }
  return null;
}

// One post-commit hook for ALL successful mutation routes. Never publish on
// validation/auth/database failure, nor include the request payload in events.
export function writeEvents(path, method, body = {}) {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) return [];
  const p = path.split('/').filter(Boolean).map(decodeURIComponent);
  const global = { ad: 'ad', announcements: 'message', theme: 'theme', 'home-layout': 'home', featured: 'featured', 'force-update': 'force_update', 'app-version': 'force_update', servers: 'servers', pricing: 'pricing', 'feedback-prompt': 'feedback' };
  if (p[0] === 'api' && p[1] === 'v1') {
    if (global[p[2]]) return [{ type: global[p[2]] }];
    if (p[2] === 'sources' && MAC.test((p[3] || '').toUpperCase())) return [{ type: 'source', mac: p[3].toUpperCase() }];
    if (['activate', 'trial-extend'].includes(p[2])) return [{ type: 'activate', ...(MAC.test(String(body.mac || '').toUpperCase()) ? { mac: body.mac.toUpperCase() } : {}) }];
    // Transfers/families can affect multiple MACs. A global invalidation is
    // intentional here, never a data broadcast (devices refetch their own data).
    if (['transfer', 'families', 'customers', 'devices', 'licenses', 'grant-trial-all', 'apps'].includes(p[2])) return [{ type: 'source' }, { type: 'license' }];
  }
  if (path === '/api/announcement') return [{ type: 'message' }];
  if (p[0] === 'admin' && p[1] === 'clients') return [{ type: 'source' }, { type: 'license' }];
  if (p[0] === 'api' && p[1] === 'self-source' && MAC.test((p[2] || '').toUpperCase())) return [{ type: 'source', mac: p[2].toUpperCase() }];
  return [];
}
export async function publishDeviceEvent(env, event) {
  const target = hub(env);
  if (!target || String(env.REALTIME_PUSH_OFF) === '1') return false;
  try {
    const res = await target.fetch('https://hub/device-notify', { method: 'POST', body: JSON.stringify(event) });
    return res.ok;
  } catch { return false; } // HTTP fallback + full resync on reconnect
}
