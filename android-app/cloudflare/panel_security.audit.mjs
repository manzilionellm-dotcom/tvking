// =========================================================
//  panel_security.audit.mjs — preuves d'audit sécurité du panel
// =========================================================
//  Aucun secret réel, aucun lien de flux. Seulement des marqueurs
//  factices (example.test, unit-test-*).
//
//  Exécution :
//    node cloudflare/panel_security.audit.mjs
// =========================================================
import worker from './worker.js';
import { apiV1 } from './api_v1.js';
import { sealField, openField } from './secret_box.js';

const ADMIN_SECRET = 'unit-test-admin-secret-not-real';
const SOURCE_KEY = 'unit-test-source-key-32b';
const M3U = 'http://example.test/playlist.m3u';
const PASSWORD = 'not-a-real-password';
const LEAK = 'HASH-LEAK-MARKER';
const ctx = { waitUntil() {}, passThroughOnException() {} };

let pass = 0;
let fail = 0;
const failures = [];
function ok(cond, name) {
  if (cond) { pass++; console.log('PASS', name); }
  else { fail++; failures.push(name); console.log('FAIL', name); }
}

function b64url(bytes) {
  return Buffer.from(bytes).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
async function signJwt(payload, secret) {
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const now = Math.floor(Date.now() / 1000);
  const body = b64url(new TextEncoder().encode(JSON.stringify({
    ...payload, iat: now, exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = new Uint8Array(await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`${header}.${body}`),
  ));
  return `${header}.${body}.${b64url(sig)}`;
}
async function pbkdf2(plain) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyMat = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(plain), { name: 'PBKDF2' }, false, ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' }, keyMat, 256,
  );
  return `pbkdf2$100000$${b64url(salt)}$${b64url(bits)}`;
}

function createDb(seed = {}) {
  const admin = [...(seed.admin_users || [])];
  const resellers = [...(seed.resellers || [])];
  const devices = [...(seed.devices || [])];
  const sources = [...(seed.device_sources || [])];
  const families = [...(seed.families || [])];
  const licenses = [...(seed.licenses || [])];
  const customers = [...(seed.customers || [])];
  const apps = [...(seed.apps || [])];
  const writes = [];
  function first(sql, args) {
    const s = sql.replace(/\s+/g, ' ');
    if (s.includes('FROM admin_users') && s.includes('COUNT')) return { n: admin.length };
    if (s.includes('FROM admin_users') && /WHERE email/.test(s)) {
      return admin.find((u) => u.email === args[0]) || null;
    }
    if (s.includes('FROM admin_users') && /WHERE id/.test(s)) {
      return admin.find((u) => u.id === args[0]) || null;
    }
    if (s.includes('FROM resellers') && /WHERE email/.test(s)) {
      return resellers.find((r) => r.email === args[0]) || null;
    }
    if (s.includes('FROM resellers') && /WHERE id/.test(s)) {
      return resellers.find((r) => r.id === args[0]) || null;
    }
    if (s.includes('FROM devices') && /WHERE mac/.test(s)) {
      return devices.find((d) => d.mac === String(args[0]).toUpperCase()) || null;
    }
    if (s.includes('FROM devices') && /WHERE id/.test(s)) {
      return devices.find((d) => d.id === args[0]) || null;
    }
    if (s.includes('FROM device_sources')) {
      return sources.find((row) => row.mac === String(args[0]).toUpperCase()) || null;
    }
    if (s.includes('FROM families')) return families.find((f) => f.id === args[0]) || null;
    if (s.includes('FROM licenses')) return licenses.find((l) => l.id === args[0]) || null;
    if (s.includes('FROM customers')) return customers.find((c) => c.id === args[0]) || null;
    if (s.includes('FROM family_links')) return seed.link || null;
    return null;
  }
  function all(sql) {
    const s = sql.replace(/\s+/g, ' ');
    if (s.includes('FROM resellers')) return { results: resellers.map((r) => ({ ...r })) };
    if (s.includes('FROM admin_users')) {
      return { results: admin.map((u) => ({ ...u })) };
    }
    if (s.includes('FROM apps')) return { results: apps.map((a) => ({ ...a })) };
    return { results: [] };
  }
  function run(sql, args) {
    writes.push({ sql, args });
    if (sql.includes('INSERT INTO admin_users')) {
      admin.push({
        id: args[0], email: args[1], password_hash: args[2],
        name: args[3], role: args[4], is_active: 1,
      });
    }
    if (sql.includes('INSERT INTO device_sources')) {
      const mac = String(args[0]).toUpperCase();
      const row = {
        mac, type: args[1], label: args[2], server_url: args[3],
        username: args[4], password: args[5], m3u_url: args[6],
        epg_url: args[7], sources_json: args[8],
      };
      const i = sources.findIndex((x) => x.mac === mac);
      if (i >= 0) sources[i] = row; else sources.push(row);
    }
    if (sql.includes('UPDATE admin_users SET password_hash')) {
      const row = admin.find((u) => u.id === args[1]);
      if (row) row.password_hash = args[0];
    }
    if (sql.includes('password_changed_at')) {
      const row = admin.find((u) => u.id === args[args.length - 1])
        || resellers.find((r) => r.id === args[args.length - 1]);
      if (row) row.password_changed_at = args[0];
    }
  }
  const db = {
    writes,
    prepare(sql) {
      const exec = (args) => ({
        first: async () => first(sql, args),
        all: async () => all(sql, args),
        run: async () => { run(sql, args); return { success: true }; },
      });
      const bound = exec([]);
      bound.bind = (...args) => exec(args);
      return bound;
    },
  };
  return db;
}

async function call(path, { method = 'GET', token, body, env, origin } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (origin) headers.Origin = origin;
  const res = await apiV1(new Request(`https://app.x${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  }), env);
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = null; }
  return { status: res.status, json, text, headers: res.headers };
}

const owner = { sub: 'adm_owner', email: 'admin', role: 'super_admin', name: 'Owner' };
const reseller = {
  sub: 'rsl_bad', email: 'bad', role: 'reseller', name: 'Bad',
  level: 'confiance', permissions: ['activate', 'sources'],
};

// ----- 1. Fuite du message d'exception -----
{
  const boom = new Proxy({}, {
    get(_t, p) { if (p === 'DB') throw new Error('SECRET-INTERNAL-XYZ'); return undefined; },
  });
  const r = await call('/api/v1/auth/me', { env: boom });
  ok(r.status === 500, 'exception -> 500');
  ok(!r.text.includes('SECRET-INTERNAL-XYZ'), '500 does not leak internal message');
}

// ----- 2. Pas de secret de secours dev-secret / change-me -----
{
  const env = { DB: createDb(), ADMIN_SECRET: '' };
  const token = await signJwt({ sub: 'adm_x', email: 'admin', role: 'super_admin' }, 'dev-secret');
  const r = await call('/api/v1/auth/me', { env, token });
  ok(r.status === 401 || r.status === 503, 'dev-secret token rejected when ADMIN_SECRET missing');
  ok(!(r.json && r.json.user), 'missing ADMIN_SECRET does not authenticate');
  const login = await call('/api/v1/auth/login', {
    method: 'POST', env, body: { email: 'admin', password: 'change-me' },
  });
  ok(!login.json || !login.json.token, 'change-me does not bootstrap a session');
}

// ----- 3. CORS : pas de * pour une origine inconnue ; panel autorisé -----
{
  const env = { DB: createDb(), ADMIN_SECRET };
  const evil = await apiV1(new Request('https://app.x/api/v1/auth/login', {
    method: 'OPTIONS',
    headers: { Origin: 'https://evil.example' },
  }), env);
  const allowEvil = evil.headers.get('access-control-allow-origin');
  ok(allowEvil !== '*' && allowEvil !== 'https://evil.example', 'CORS does not allow evil origin');
  const panel = await apiV1(new Request('https://app.x/api/v1/auth/login', {
    method: 'OPTIONS',
    headers: { Origin: 'https://tvking-admin.pages.dev' },
  }), env);
  ok(panel.headers.get('access-control-allow-origin') === 'https://tvking-admin.pages.dev',
    'CORS allows the admin panel origin');
}

// ----- 4. Jeton alg=none rejeté -----
{
  const env = {
    DB: createDb({
      admin_users: [{ id: 'adm_owner', email: 'admin', role: 'super_admin', is_active: 1, password_hash: 'x' }],
    }),
    ADMIN_SECRET,
  };
  const h = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'none', typ: 'JWT' })));
  const p = b64url(new TextEncoder().encode(JSON.stringify({
    sub: 'adm_owner', role: 'super_admin', exp: Math.floor(Date.now() / 1000) + 3600,
  })));
  const r = await call('/api/v1/auth/me', { env, token: `${h}.${p}.` });
  ok(r.status === 401, 'alg=none token rejected');
}

// ----- 5. Session : compte désactivé et mot de passe changé -----
{
  const env = {
    DB: createDb({
      admin_users: [{
        id: 'adm_owner', email: 'admin', role: 'super_admin', is_active: 0,
        password_hash: 'x', password_changed_at: null,
      }],
    }),
    ADMIN_SECRET,
  };
  const token = await signJwt(owner, ADMIN_SECRET);
  const r = await call('/api/v1/auth/me', { env, token });
  ok(r.status === 401, 'inactive admin token rejected');

  const env2 = {
    DB: createDb({
      admin_users: [{
        id: 'adm_owner', email: 'admin', role: 'super_admin', is_active: 1,
        password_hash: 'x', password_changed_at: Date.now() + 120000,
      }],
    }),
    ADMIN_SECRET,
  };
  const r2 = await call('/api/v1/stats/overview', { env: env2, token });
  ok(r2.status === 401, 'token issued before password change rejected');
}

// ----- 6. IDOR revendeur : source, famille, licence, client -----
{
  const db = createDb({
    resellers: [{
      id: 'rsl_bad', email: 'bad', status: 'active', level: 'confiance',
      permissions: '["activate","sources"]', is_active: 1,
    }],
    devices: [{ id: 'dev_v', mac: 'MK:11:22:33:44:55', reseller_id: 'rsl_owner' }],
    device_sources: [{
      mac: 'MK:11:22:33:44:55', type: 'xtream', password: PASSWORD,
      m3u_url: null, username: 'user', sources_json: null,
    }],
    families: [{ id: 'fam_other', reseller_id: 'rsl_owner', name: 'Autre', source_json: '{}' }],
    licenses: [{ id: 'lic_victim', reseller_id: 'rsl_owner', plan: '1y', expires_at: 1 }],
    customers: [{
      id: 'cus_victim', reseller_id: 'rsl_owner', email: 'c@example.test',
      password_hash: LEAK, name: 'C',
    }],
    apps: [{ id: 'app_1', name: 'A', default_iptv_server: 'http://secret-server.example' }],
  });
  const env = { DB: db, ADMIN_SECRET };
  const token = await signJwt(reseller, ADMIN_SECRET);
  const src = await call('/api/v1/sources/MK:11:22:33:44:55', { env, token });
  ok(src.status === 403, 'reseller cannot read another device source');
  ok(!src.text.includes(PASSWORD), 'other device password not in response');
  const put = await call('/api/v1/sources/MK:11:22:33:44:55', {
    method: 'PUT', env, token,
    body: { source: { type: 'm3u', m3u_url: M3U } },
  });
  ok(put.status === 403, 'reseller cannot overwrite another device source');
  const fam = await call('/api/v1/families/fam_other', { method: 'DELETE', env, token });
  ok(fam.status === 403, 'reseller cannot delete another family');
  ok(!db.writes.some((w) => w.sql.includes('DELETE FROM families')),
    'family delete was not executed');
  const renew = await call('/api/v1/licenses/lic_victim/renew', {
    method: 'POST', env, token, body: { plan: 'lifetime' },
  });
  ok(renew.status === 403, 'reseller cannot renew a foreign license');
  ok(!db.writes.some((w) => w.sql.includes('UPDATE licenses')),
    'license update was not executed');
  const cus = await call('/api/v1/customers/cus_victim', { env, token });
  ok(cus.status === 403, 'reseller cannot read another customer');
  ok(!cus.text.includes(LEAK), 'customer password hash not leaked to reseller');
  const dev = await call('/api/v1/devices', {
    method: 'POST', env, token,
    body: { customer_id: 'cus_victim', mac: 'MK:10:20:30:40:50' },
  });
  ok(dev.status === 403, 'reseller cannot create a raw device');
  const apps = await call('/api/v1/apps', { env, token });
  ok(!apps.text.includes('secret-server.example'), 'reseller apps list hides default server url');
}

// ----- 7. Le propriétaire ne reçoit pas le hash, et la sauvegarde non plus -----
{
  const db = createDb({
    admin_users: [{
      id: 'adm_owner', email: 'admin', role: 'super_admin', is_active: 1, password_hash: 'x',
    }],
    customers: [{
      id: 'cus_victim', reseller_id: null, email: 'c@example.test',
      password_hash: LEAK, name: 'C',
    }],
    resellers: [{ id: 'rsl_owner', email: 'o@example.test', password_hash: LEAK, status: 'active' }],
  });
  const env = { DB: db, ADMIN_SECRET };
  const token = await signJwt(owner, ADMIN_SECRET);
  const cus = await call('/api/v1/customers/cus_victim', { env, token });
  ok(cus.status === 200, 'owner can read a customer');
  ok(!cus.text.includes(LEAK), 'owner customer payload strips password_hash');
  const backup = await call('/api/v1/backup', { env, token });
  ok(backup.status === 200, 'owner can download backup');
  ok(!backup.text.includes(LEAK), 'backup strips password hashes');
}

// ----- 8. Chiffrement au repos + schéma d'URL M3U -----
{
  const sealed = await sealField({ SOURCE_ENCRYPTION_KEY: SOURCE_KEY }, PASSWORD);
  ok(sealed.startsWith('enc1.') && !sealed.includes(PASSWORD), 'seal hides the password');
  ok(await openField({ SOURCE_ENCRYPTION_KEY: SOURCE_KEY }, sealed) === PASSWORD, 'open restores the password');
  ok(await openField({ SOURCE_ENCRYPTION_KEY: 'another-test-key-32chars' }, sealed) === null,
    'wrong key does not return ciphertext');

  const db = createDb({
    admin_users: [{
      id: 'adm_owner', email: 'admin', role: 'super_admin', is_active: 1, password_hash: 'x',
    }],
  });
  const env = { DB: db, ADMIN_SECRET, SOURCE_ENCRYPTION_KEY: SOURCE_KEY };
  const token = await signJwt(owner, ADMIN_SECRET);
  const put = await call('/api/v1/sources/MK:AA:BB:CC:DD:EE', {
    method: 'PUT', env, token,
    body: { source: { type: 'm3u', m3u_url: M3U } },
  });
  ok(put.status === 200, 'owner can store an m3u source');
  const stored = db.writes.find((w) => w.sql.includes('INSERT INTO device_sources'));
  const storedUrl = stored ? stored.args[6] : '';
  const storedJson = stored ? String(stored.args[8]) : '';
  ok(String(storedUrl).startsWith('enc1.') && !String(storedUrl).includes('example.test'),
    'm3u url is encrypted at rest');
  ok(!storedJson.includes('example.test'), 'sources_json does not contain the plaintext url');
  const got = await call('/api/v1/sources/MK:AA:BB:CC:DD:EE', { env, token });
  ok(got.json && got.json.source && got.json.source.m3u_url === M3U,
    'owner read decrypts the m3u url');

  const bad = await call('/api/v1/sources/MK:AA:BB:CC:DD:EF', {
    method: 'PUT', env, token,
    body: { source: { type: 'm3u', m3u_url: 'javascript:alert(1)' } },
  });
  ok(bad.status === 400, 'javascript m3u url rejected');
}

// ----- 9. Self-source : pas de CORS *, et écriture chiffrée -----
{
  const bare = await worker.fetch(new Request('https://app.x/api/self-source/MK:AA:BB:CC:DD:EE', {
    headers: { Origin: 'https://evil.example' },
  }), {}, ctx);
  ok(!bare.headers.get('access-control-allow-origin'), 'self-source has no CORS star');

  const db = createDb();
  const res = await worker.fetch(new Request('https://app.x/api/self-source/MK:AA:BB:CC:DD:EE', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://evil.example' },
    body: JSON.stringify({ type: 'm3u', m3u_url: M3U }),
  }), { DB: db, SOURCE_ENCRYPTION_KEY: SOURCE_KEY }, ctx);
  ok(!res.headers.get('access-control-allow-origin'), 'self-source write has no CORS star');
  const write = db.writes.find((w) => w.sql.includes('INSERT INTO device_sources'));
  ok(write && String(write.args[6]).startsWith('enc1.') && !String(write.args[6]).includes('example.test'),
    'self-source encrypts m3u url at rest');
}

// ----- 10. Lien M3U public : pas de redirection javascript: -----
{
  const db = createDb();
  db.prepare = ((orig) => (sql) => {
    const stmt = orig(sql);
    return {
      bind(...args) {
        const bound = stmt.bind(...args);
        return {
          first: async () => {
            if (sql.includes('family_links')) return { family_id: 'fam_1' };
            if (sql.includes('FROM families')) {
              return { source_json: JSON.stringify({ type: 'm3u', m3u_url: 'javascript:alert(1)' }) };
            }
            return bound.first();
          },
          all: () => bound.all(),
          run: () => bound.run(),
        };
      },
    };
  })(db.prepare.bind(db));
  const res = await worker.fetch(new Request('https://app.x/api/m3u/tokentest'), { DB: db }, ctx);
  const loc = res.headers.get('location') || '';
  ok(res.status !== 302 && !loc.toLowerCase().startsWith('javascript:'),
    'public m3u does not redirect to javascript');
}

// ----- 11. L'app reçoit l'URL déchiffrée (pas le ciphertext) -----
{
  const sealed = await sealField({ SOURCE_ENCRYPTION_KEY: SOURCE_KEY }, M3U);
  const db = createDb({
    device_sources: [{
      mac: 'MK:AB:CD:EF:01:23', type: 'm3u', label: 'L', server_url: null,
      username: null, password: null, m3u_url: sealed, epg_url: null,
      sources_json: JSON.stringify([{ type: 'm3u', m3u_url: sealed }]),
    }],
  });
  const res = await worker.fetch(
    new Request('https://app.x/api/device-source/MK:AB:CD:EF:01:23'),
    { DB: db, SOURCE_ENCRYPTION_KEY: SOURCE_KEY }, ctx,
  );
  const body = await res.json();
  ok(body && body.source && body.source.m3u_url === M3U, 'device-source decrypts m3u for the app');
  ok(!JSON.stringify(body).includes('enc1.'), 'device-source does not return ciphertext');
}

// ----- 12. En-têtes de sécurité HTML + fichier Pages -----
{
  const res = await worker.fetch(new Request('https://app.x/'), {}, ctx);
  ok(res.headers.get('x-content-type-options') === 'nosniff', 'HTML nosniff');
  ok((res.headers.get('x-frame-options') || '').toUpperCase() === 'DENY', 'HTML denies framing');
  let headers = '';
  try {
    const { readFileSync } = await import('node:fs');
    headers = readFileSync(new URL('../admin-panel/public/_headers', import.meta.url), 'utf8');
  } catch (_) { headers = ''; }
  ok(headers.includes('Content-Security-Policy'), 'panel _headers has CSP');
  ok(headers.includes('frame-ancestors'), 'panel CSP blocks framing');
  ok(headers.includes('X-Content-Type-Options'), 'panel _headers nosniff');
}

// ----- 13. Cookie ignoré (pas de session cookie → pas de CSRF classique) -----
{
  const env = { DB: createDb(), ADMIN_SECRET };
  const res = await apiV1(new Request('https://app.x/api/v1/auth/me', {
    headers: { Cookie: 'auth_token=stolen' },
  }), env);
  ok(res.status === 401, 'cookie is not accepted as a session');
}

console.log(`\n${pass} passed, ${fail} failed`);
if (failures.length) {
  console.log('FAILED:');
  for (const name of failures) console.log(' -', name);
}
process.exit(fail ? 1 : 0);
