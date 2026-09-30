// =========================================================
//  zuno_security.test.mjs — Filet sur les trous de l'audit
// =========================================================
//  node cloudflare/zuno_security.test.mjs
//  Aucun secret de production : les valeurs ici sont des leurres
//  de test, générées pour la vérification.
// =========================================================
import worker from './worker.js';
import {
  backupAllowed,
  deviceReadDecision,
  enrollDecision,
  legacyCredentialsAllowed,
} from './device_guard.js';
import { openString, redactCredentialUrl, sealString } from './source_crypto.js';
import { sourceFingerprint } from './source_revoke.js';
import { hashDeviceSecret } from './device_guard.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const TEST_ADMIN = 'unit-test-admin-secret';
const BOX_SECRET = 'box-secret-unit-test-0123456789abcdef';
const PLAYLIST_PASS = 'playlist-pass-unit';
const MAC = 'MK:AA:BB:CC:DD:11';

function memoryDb() {
  const t = {
    device_secrets: [],
    devices: [],
    licenses: [],
    device_sources: [],
    device_backups: [],
    rate_limits: [],
    customers: [],
    admin_users: [],
  };
  const flags = { failDevices: false };
  function prepare(sql) {
    const q = sql.replace(/\s+/g, ' ').trim();
    // D1 accepte prepare(sql).run() ET prepare(sql).bind(...).run().
    const stmt = (args) => {
      const op = apply(q, args, t, flags);
      return {
        first: async () => op.first,
        run: async () => op.run,
        all: async () => ({ results: op.all || [] }),
      };
    };
    const bound = stmt([]);
    return {
      bind(...args) { return stmt(args); },
      run: bound.run,
      first: bound.first,
      all: bound.all,
    };
  }
  return { prepare, t, flags };
}

function apply(q, args, t, flags) {
  if (/^CREATE |^ALTER |^CREATE INDEX/i.test(q)) return { run: {} };
  if (flags.failDevices && /FROM devices/i.test(q)) {
    throw new Error('d1 down');
  }
  if (q.includes('FROM rate_limits')) {
    const row = t.rate_limits.find((r) => r.k === args[0]);
    return { first: row || null };
  }
  if (q.includes('INSERT INTO rate_limits')) {
    const k = args[0];
    const now = args[1];
    const prev = t.rate_limits.find((r) => r.k === k);
    if (prev) { prev.count = 1; prev.window_start = now; }
    else t.rate_limits.push({ k, count: 1, window_start: now });
    return { run: {} };
  }
  if (q.includes('UPDATE rate_limits SET count')) {
    const row = t.rate_limits.find((r) => r.k === args[0]);
    if (row) row.count += 1;
    return { run: {} };
  }
  if (q.includes('FROM device_secrets')) {
    return { first: t.device_secrets.find((r) => r.mac === args[0]) || null };
  }
  if (q.includes('INSERT INTO device_secrets')) {
    const row = {
      mac: args[0], secret_hash: args[1], android_id: args[2], updated_at: args[3],
    };
    const i = t.device_secrets.findIndex((r) => r.mac === row.mac);
    if (i >= 0) t.device_secrets[i] = row;
    else t.device_secrets.push(row);
    return { run: {} };
  }
  if (q.includes('FROM devices') && q.includes('android_id') && !q.includes('reseller_id')) {
    const row = t.devices.find((r) => r.mac === args[0]);
    return { first: row ? { android_id: row.android_id } : null };
  }
  if (q.includes('SELECT id FROM devices')) {
    const row = t.devices.find((r) => r.mac === args[0]);
    return { first: row ? { id: row.id } : null };
  }
  if (q.includes('first_seen_at') && q.includes('FROM devices')) {
    const row = t.devices.find((r) => r.mac === args[0]);
    return { first: row || null };
  }
  if (q.includes('reseller_id, customer_id FROM devices') || q.includes('reseller_id, customer_id')) {
    const row = t.devices.find((r) => r.mac === args[0]);
    return { first: row || null };
  }
  if (q.includes('FROM licenses')) {
    const row = t.licenses.find((r) => r.device_id === args[0]);
    return { first: row || null };
  }
  if (q.includes('FROM device_sources')) {
    return { first: t.device_sources.find((r) => r.mac === args[0]) || null };
  }
  if (q.includes('FROM device_backups')) {
    return { first: t.device_backups.find((r) => r.mac === args[0]) || null };
  }
  if (q.includes('INSERT INTO device_backups')) {
    const row = { mac: args[0], data_json: args[1], updated_at: args[2] };
    const i = t.device_backups.findIndex((r) => r.mac === row.mac);
    if (i >= 0) t.device_backups[i] = row;
    else t.device_backups.push(row);
    return { run: {} };
  }
  if (q.includes('FROM customers WHERE id')) {
    return { first: t.customers.find((r) => r.id === args[0]) || null };
  }
  if (q.includes('reseller_id FROM customers')) {
    const row = t.customers.find((r) => r.id === args[0]);
    return { first: row ? { reseller_id: row.reseller_id } : null };
  }
  if (q.includes('COUNT(*)')) return { first: { n: t.admin_users.length } };
  return { first: null, run: {} };
}

function b64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
async function signJwt(payload, secret) {
  const h = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const now = Math.floor(Date.now() / 1000);
  const p = b64url(new TextEncoder().encode(JSON.stringify({
    ...payload, iat: now, exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = b64url(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${sig}`;
}

// ----- Décisions pures -----
ok(legacyCredentialsAllowed({ hasDb: false, readFailed: false, status: null }) === false,
  'sans base, pas de codes');
ok(legacyCredentialsAllowed({ hasDb: true, readFailed: true, status: null }) === false,
  'lecture licence en erreur, pas de codes');
ok(legacyCredentialsAllowed({
  hasDb: true, readFailed: false, status: { expired: true },
}) === false, 'licence expirée, pas de codes');
ok(legacyCredentialsAllowed({
  hasDb: true, readFailed: false, status: null,
}) === false, 'box inconnue, pas de codes');
ok(deviceReadDecision({ enrolled: true, secretOk: false, legacyOk: true }) === 'deny',
  'box enrôlée sans secret → refus');
ok(deviceReadDecision({ enrolled: false, secretOk: false, legacyOk: true }) === 'legacy',
  'ancienne box, licence lisible → lecture encore possible');
ok(backupAllowed({ enrolled: false, secretOk: false }) === false, 'backup sans secret refusé');
ok(backupAllowed({ enrolled: true, secretOk: true }) === true, 'backup avec secret accepté');
ok(enrollDecision({
  hasSecret: true, presentedMatches: false, knownAndroidId: 'abc', presentedAndroidId: 'nope',
}) === 'deny', 'enrôlement avec le mauvais android id refusé');
ok(enrollDecision({
  hasSecret: true, presentedMatches: false, knownAndroidId: 'abc', presentedAndroidId: 'abc',
}) === 'rotate', 'réinstallation : même android id, nouveau secret');

const sealed = await sealString('mot-de-passe', 'unit-key');
ok(sealed.startsWith('enc1:') && !sealed.includes('mot-de-passe'), 'chiffrement sans le clair');
ok(await openString(sealed, 'unit-key') === 'mot-de-passe', 'déchiffrement');
ok(await openString('ancien-clair', 'unit-key') === 'ancien-clair', 'ligne ancienne en clair lisible');
ok(await openString(sealed, '') === null, 'chiffré illisible sans clé');
const redacted = redactCredentialUrl('http://user:secret@exemple.test/get.php?username=u&password=p');
ok(!redacted.includes('secret') && !redacted.includes('password=p'), 'URL M3U sans identifiants');

// ----- Worker -----
const db = memoryDb();
const hash = await hashDeviceSecret(BOX_SECRET);
db.t.device_secrets.push({ mac: MAC, secret_hash: hash, android_id: 'android-1', updated_at: 1 });
db.t.devices.push({
  id: 'dev1', mac: MAC, first_seen_at: Date.now(), block_status: null,
  android_id: 'android-1', reseller_id: 'rsl_owner', customer_id: 'cus1',
});
db.t.licenses.push({
  device_id: 'dev1', lstatus: 'active', expires_at: Date.now() + 86400000,
});
db.t.device_sources.push({
  mac: MAC, type: 'xtream', label: 'Liste', server_url: 'http://exemple.test',
  username: 'user', password: PLAYLIST_PASS, m3u_url: null, epg_url: null,
  sources_json: null, updated_at: 1,
});
db.t.customers.push({ id: 'cus1', reseller_id: 'rsl_owner', name: 'Client' });
db.t.customers.push({ id: 'cus_other', reseller_id: 'rsl_other', name: 'Autre' });

const env = { DB: db, ADMIN_SECRET: TEST_ADMIN };

let r = await worker.fetch(new Request('https://app.x/api/v1/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'admin', password: 'x' }),
}), { DB: db }, ctx);
let body = await r.json();
ok(r.status === 503 && body.error === 'admin_unconfigured' && !body.token,
  'login sans secret admin → 503, pas de jeton');

r = await worker.fetch(new Request(`https://app.x/api/device-source/${MAC}`), env, ctx);
body = await r.json();
ok(r.status === 401 && !JSON.stringify(body).includes(PLAYLIST_PASS),
  'device-source enrôlé sans secret → pas de mot de passe');

r = await worker.fetch(new Request(`https://app.x/api/device-source/${MAC}`, {
  headers: { 'X-Device-Secret': BOX_SECRET },
}), env, ctx);
body = await r.json();
ok(r.status === 200 && body.source && body.source.password === PLAYLIST_PASS,
  'device-source avec le secret de la box → codes délivrés');
ok(sourceFingerprint({ type: 'xtream', server_url: 'http://Exemple.test/', username: 'user' })
  === 'xtream|http://exemple.test|user',
  'empreinte xtream identique à la box');
r = await worker.fetch(new Request(`https://app.x/api/status/${MAC}`), env, ctx);
body = await r.json();
ok(r.status === 200 && typeof body.source_rev === 'number' && Array.isArray(body.revoked)
  && !JSON.stringify(body).includes(PLAYLIST_PASS),
  'status porte source_rev et revoked, jamais le mot de passe');

r = await worker.fetch(new Request(`https://app.x/api/backup/${MAC}`, { method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ data: { v: 1 } }),
}), env, ctx);
ok(r.status === 401, 'backup PUT sans secret → 401');

r = await worker.fetch(new Request(`https://app.x/api/backup/${MAC}`), env, ctx);
body = await r.json();
ok(r.status === 401 && body.data == null, 'backup GET sans secret → rien');

r = await worker.fetch(new Request(`https://app.x/api/backup/${MAC}`, {
  headers: { 'X-Device-Secret': BOX_SECRET },
  method: 'PUT',
  body: JSON.stringify({ data: { v: 1, playlists: [] } }),
}), env, ctx);
ok(r.status === 200, 'backup PUT avec secret → accepté');

// Ancienne box : pas d'empreinte, licence OK → les codes passent encore.
const legacy = memoryDb();
legacy.t.devices.push({
  id: 'devL', mac: MAC, first_seen_at: Date.now(), block_status: null, android_id: 'android-1',
});
legacy.t.licenses.push({
  device_id: 'devL', lstatus: 'active', expires_at: Date.now() + 86400000,
});
legacy.t.device_sources.push({
  mac: MAC, type: 'xtream', password: PLAYLIST_PASS, username: 'u',
  server_url: 'http://exemple.test', sources_json: null,
});
r = await worker.fetch(new Request(`https://app.x/api/device-source/${MAC}`),
  { DB: legacy, ADMIN_SECRET: TEST_ADMIN }, ctx);
body = await r.json();
ok(r.status === 200 && body.source && body.source.password === PLAYLIST_PASS,
  'ancienne box sans secret, licence lisible → compatibilité');

// Base qui tousse : plus de mot de passe.
legacy.flags.failDevices = true;
r = await worker.fetch(new Request(`https://app.x/api/device-source/${MAC}`),
  { DB: legacy, ADMIN_SECRET: TEST_ADMIN }, ctx);
body = await r.json();
ok(!JSON.stringify(body).includes(PLAYLIST_PASS),
  'panne de lecture licence → pas de mot de passe');

// Revendeur sur la box d'un autre.
const token = await signJwt(
  { sub: 'rsl_intrus', role: 'reseller', email: 'intrus@exemple.test' },
  TEST_ADMIN,
);
r = await worker.fetch(new Request(`https://app.x/api/v1/sources/${MAC}`, {
  headers: { Authorization: `Bearer ${token}` },
}), env, ctx);
body = await r.json();
ok(r.status === 403 && !JSON.stringify(body).includes(PLAYLIST_PASS),
  'revendeur, MAC d\'un autre → 403 sans codes');

r = await worker.fetch(new Request('https://app.x/api/v1/customers/cus_other', {
  headers: { Authorization: `Bearer ${token}` },
}), env, ctx);
ok(r.status === 403, 'revendeur, fiche client d\'un autre → 403');

const owner = await signJwt(
  { sub: 'adm_1', role: 'super_admin', email: 'admin@exemple.test' },
  TEST_ADMIN,
);
r = await worker.fetch(new Request(`https://app.x/api/v1/sources/${MAC}`, {
  headers: { Authorization: `Bearer ${owner}` },
}), env, ctx);
body = await r.json();
ok(r.status === 200 && body.source && body.source.password === PLAYLIST_PASS,
  'propriétaire lit toujours la source de la box');

r = await worker.fetch(new Request('https://app.x/api/v1/boxes/live'), env, ctx);
ok(r.status === 401, 'état en direct sans jeton → 401');

r = await worker.fetch(new Request(`https://app.x/api/box/wait/${MAC}?timeout=200`), env, ctx);
body = await r.json();
ok(r.status === 401 && body.error === 'device_secret_required'
  && !JSON.stringify(body).includes(PLAYLIST_PASS),
  'attente sans secret de box → 401');

r = await worker.fetch(new Request(`https://app.x/api/box/wait/${MAC}?timeout=200`, {
  headers: { 'X-Device-Secret': 'pas-le-bon-secret-0123456789abcdef' },
}), env, ctx);
ok(r.status === 401, 'attente avec un mauvais secret → 401');

r = await worker.fetch(new Request(`https://app.x/api/box/ack/${MAC}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: '{}',
}), env, ctx);
ok(r.status === 401, 'accusé sans secret → 401');

r = await worker.fetch(new Request(`https://app.x/api/box/wait/${MAC}?timeout=200`, {
  headers: { 'X-Device-Secret': BOX_SECRET },
}), env, ctx);
body = await r.json();
ok(r.status === 200 && body.timeout === true && Array.isArray(body.box)
  && !JSON.stringify(body).includes(PLAYLIST_PASS),
  'attente avec le secret, rien en file, pas de mot de passe');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
