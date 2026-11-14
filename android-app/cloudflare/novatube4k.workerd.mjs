// Vérification du candidat exact dans workerd/Miniflare, sans nodejs_compat.
// D1 et RealtimeHub sont locaux. Les secrets sont créés pour ce processus ;
// chaque sous-requête HTTP sortante est interceptée et refusée avant réseau.
// Usage : node novatube4k.workerd.mjs [chemin/novatube4k-live-entry.js]
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { Miniflare, Log, LogLevel } from 'miniflare';

const here = dirname(fileURLToPath(import.meta.url));
const candidate = resolve(process.argv[2] || join(here, '../../../atlas4k-evidence/release/novatube4k-live-entry.js'));
const rawMac = 'AABBCCDDEE01';
const deviceKey = randomBytes(32).toString('hex');
const wrongKey = randomBytes(32).toString('hex');
const adminSecret = randomBytes(32).toString('hex');
const appId = 'app_novatube4k';
const outbound = [];
const started = Date.now();
let passed = 0;
let currentStep = 'startup';

const mf = new Miniflare({
  host: '127.0.0.1', port: 0,
  modules: true,
  modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }],
  scriptPath: candidate,
  modulesRoot: dirname(candidate),
  cf: false,
  compatibilityDate: '2025-05-01',
  compatibilityFlags: [],
  d1Databases: { DB: 'novatube4k-workerd-fixture' },
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  bindings: {
    ADMIN_SECRET: adminSecret,
    SECRETS_KEY: randomBytes(32).toString('hex'),
    ACCOUNT_ENCRYPTION_KEY: randomBytes(32).toString('hex'),
    DEVICE_TOKEN_SECRET: randomBytes(32).toString('hex'),
    GOLD_PANEL_API_KEY: 'fixtureOnlyKeyNeverUsedOnTheNetwork1234',
    DEFAULT_SERVERS: '[]',
    PANEL_ORIGINS: 'https://atlas-console-k7q2.vercel.app',
  },
  // Ce service remplace le réseau du candidat, y compris les fetch lancés
  // dans waitUntil. Les bindings D1/DO locaux n'empruntent pas ce service.
  outboundService: async (request) => {
    const url = new URL(request.url);
    outbound.push({ host: url.host, path: url.pathname });
    return new Response('{"error":"external_network_forbidden_in_fixture"}', {
      status: 503, headers: { 'Content-Type': 'application/json' },
    });
  },
  log: new Log(LogLevel.WARN),
});

async function step(name, fn) {
  currentStep = name;
  const result = await fn();
  passed++;
  console.log('PASS ' + name);
  return result;
}

async function api(method, path, { token, body, headers: extra = {}, text } = {}) {
  const headers = {
    'Content-Type': 'application/json',
    'CF-Connecting-IP': '192.0.2.83',
    'CF-IPCountry': 'FR',
    ...extra,
  };
  if (token) headers.Authorization = 'Bearer ' + token;
  const response = await mf.dispatchFetch('https://fixture.test' + path, {
    method, headers,
    body: method === 'GET' ? undefined : text ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  const responseText = await response.text();
  let data;
  try { data = JSON.parse(responseText); } catch { data = null; }
  return { status: response.status, data, headers: response.headers };
}

async function device(action, body = {}, key = deviceKey) {
  return api('POST', '/api/novatube4k/' + action, {
    body: { raw_mac: rawMac, ...body },
    headers: { 'X-Device-Key': key },
  });
}

function status(result, expected) {
  assert.equal(result.status, expected, 'HTTP status; safe error=' + (result.data?.error || 'none'));
}

try {
  console.log(JSON.stringify({
    runtime: 'workerd via Miniflare', compatibility_date: '2025-05-01', compatibility_flags: [],
    candidate, candidate_sha256: createHash('sha256').update(readFileSync(candidate)).digest('hex'),
    module_sha256: createHash('sha256').update(readFileSync(join(dirname(candidate), 'novatube4k.js'))).digest('hex'),
    wrapper_sha256: createHash('sha256').update(readFileSync(join(dirname(candidate), 'novatube4k-wrapper.js'))).digest('hex'),
    external_network: 'intercepted and denied',
  }));
  await mf.ready;
  const db = await mf.getD1Database('DB');
  await step('schéma D1 local et RealtimeHub réel disponibles', async () => {
    const schema = readFileSync(join(here, 'schema.sql'), 'utf8');
    for (const statement of schema.split(/;\s*(?:\n|$)/).map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) {
      await db.prepare(statement).run();
    }
    try { await db.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run(); } catch (_) {}
    const namespace = await mf.getDurableObjectNamespace('RT_HUB');
    assert.ok(namespace.get(namespace.idFromName('novatube4k-local-check')));
    assert.ok(await db.prepare("SELECT id FROM apps WHERE id='app_7motion'").first());
  });

  await step('state et ack inconnus : 401, aucun enrôlement', async () => {
    status(await device('state'), 401);
    status(await device('ack', { source_rev: 1, applied: true }), 401);
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM devices').first()).n, 0);
  });

  const mac = await step('register : appareil inactif, licence dédiée expires_at=0 et présence', async () => {
    const r = await device('register');
    status(r, 200);
    assert.equal(r.data.created, true);
    assert.equal(r.data.active, false);
    assert.equal(r.data.status, 'inactive');
    assert.equal(r.data.expires_at, 0);
    assert.equal(r.data.app_id, appId);
    assert.deepEqual(r.data.sources, []);
    assert.match(r.data.mac, /^MK(?::[0-9A-F]{2}){5}$/);
    const lic = await db.prepare('SELECT app_id,status,expires_at FROM licenses').first();
    assert.deepEqual(lic, { app_id: appId, status: 'inactive', expires_at: 0 });
    const online = await db.prepare('SELECT last_seen,channel FROM presence WHERE mac=?').bind(r.data.mac).first();
    assert.ok(online.last_seen > started - 1000);
    assert.equal(online.channel, '');
    return r.data.mac;
  });

  await step('clé erronée 401, claim concurrent 409, register identique idempotent', async () => {
    status(await device('state', {}, wrongKey), 401);
    status(await device('register', {}, wrongKey), 409);
    const replay = await device('register');
    status(replay, 200);
    assert.equal(replay.data.created, false);
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM devices').first()).n, 1);
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM licenses').first()).n, 1);
  });

  await step('corps trop volumineux refusé sans attente flottante', async () => {
    const large = await api('POST', '/api/novatube4k/state', {
      headers: { 'X-Device-Key': deviceKey },
      text: JSON.stringify({ raw_mac: rawMac, padding: 'x'.repeat(5000) }),
    });
    status(large, 413);
    assert.ok(large.headers.get('cache-control').includes('no-store'));
  });

  await step('activation anonyme refusée par les contrôles originaux', async () => {
    const denied = await api('POST', '/api/v1/activate', { body: { mac, plan: 'yearly' } });
    assert.ok([401, 403].includes(denied.status));
    assert.equal((await device('state')).data.active, false);
  });

  const token = await step('authentification admin locale par la vraie route JWT', async () => {
    const logged = await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: adminSecret } });
    status(logged, 200);
    assert.ok(typeof logged.data.token === 'string' && logged.data.token.length > 40);
    return logged.data.token;
  });

  await step('origine non autorisée refusée même avec JWT de fixture', async () => {
    const denied = await api('POST', '/api/v1/activate', {
      token, body: { mac, plan: 'yearly' }, headers: { Origin: 'https://untrusted.example.test' },
    });
    status(denied, 403);
  });

  await step('fixture Gold activée pour détecter toute fuite vers son hook', async () => {
    const r = await api('POST', '/api/v1/gold/config', { token, body: { gold_enabled: '1', gold_trial_enabled: '1' } });
    status(r, 200);
    assert.equal(outbound.length, 0);
  });

  const licenseId = await step('activation panel authentifiée remappée vers NOVATUBE uniquement', async () => {
    const r = await api('POST', '/api/v1/activate', {
      token, body: { mac, plan: 'yearly', app_id: 'app_7motion' },
      headers: { 'Idempotency-Key': crypto.randomUUID(), 'X-Request-Id': 'novatube-workerd-activation' },
    });
    status(r, 201);
    assert.equal(r.data.credits_charged, 0);
    const rows = await db.prepare('SELECT app_id,status FROM licenses').all();
    assert.deepEqual(rows.results, [{ app_id: appId, status: 'active' }]);
    const state = await device('state');
    status(state, 200);
    assert.equal(state.data.active, true);
    return r.data.license_id;
  });

  let sourceOrder = await step('publication M3U et Xtream depuis la route panel existante', async () => {
    const r = await api('PUT', '/api/v1/sources/' + encodeURIComponent(mac), {
      token,
      body: { sources: [
        { type: 'm3u', label: 'M3U fixture', m3u_url: 'https://list.example.test/fixture.m3u?token=fixture-only' },
        { type: 'xtream', label: 'Xtream fixture', server_url: 'https://xtream.example.test/prefix', username: 'fixture-user', password: 'fixture-password', enabled: false },
      ] },
      headers: { 'X-Request-Id': 'novatube-workerd-source' },
    });
    status(r, 200);
    assert.equal(r.data.rev, 1);
    assert.ok(r.data.order_id);
    return r.data.order_id;
  });

  const initialIds = await step('state déchiffre les deux sources et fournit des identités stables', async () => {
    const r = await device('state');
    status(r, 200);
    assert.equal(r.data.active, true);
    assert.equal(r.data.sources_ok, true);
    assert.equal(r.data.source_rev, 1);
    assert.equal(r.data.sources.length, 2);
    assert.equal(r.data.sources[1].password, 'fixture-password');
    assert.equal(r.data.sources[1].enabled, false);
    assert.ok(r.data.sources.every((s) => /^n4k_[a-f0-9]{64}$/.test(s.id)));
    assert.notEqual(r.data.sources[0].id, r.data.sources[1].id);
    const binding = await db.prepare('SELECT last_served_rev FROM novatube4k_devices').first();
    assert.equal(binding.last_served_rev, 1);
    assert.notEqual((await db.prepare('SELECT state FROM box_orders WHERE order_id=?').bind(sourceOrder).first()).state, 'applied');
    return r.data.sources.map((s) => s.id);
  });

  await step('renommer ou changer mot de passe conserve l’identité, un autre compte reste distinct', async () => {
    const republished = await api('PUT', '/api/v1/sources/' + encodeURIComponent(mac), {
      token, body: { sources: [
        { type: 'm3u', label: 'Renamed M3U', m3u_url: 'https://list.example.test/fixture.m3u?token=fixture-only' },
        { type: 'xtream', label: 'Renamed Xtream', server_url: 'https://XTREAM.example.test:443/prefix/', username: 'fixture-user', password: 'changed-password', enabled: false },
        { type: 'xtream', label: 'Second account', server_url: 'https://xtream.example.test/prefix', username: 'fixture-other-user', password: 'another-password' },
      ] },
    });
    status(republished, 200);
    assert.equal(republished.data.rev, 2);
    sourceOrder = republished.data.order_id;
    const r = await device('state');
    status(r, 200);
    assert.equal(r.data.sources_ok, true);
    assert.equal(r.data.source_rev, 2);
    assert.deepEqual(r.data.sources.slice(0, 2).map((s) => s.id), initialIds);
    assert.notEqual(r.data.sources[2].id, r.data.sources[1].id);
    const stored = JSON.parse((await db.prepare('SELECT sources_json FROM device_sources WHERE mac=?').bind(mac).first()).sources_json);
    assert.ok(stored.every((s) => s.id === undefined), 'ids ajoutés à la réponse dédiée uniquement');
  });

  await step('anciennes routes publiques refusées pour cette MAC, y compris encodée', async () => {
    for (const path of [
      '/api/device-source/' + mac, '/api/device-source/' + encodeURIComponent(mac),
      '/config/' + mac, '/api/self-source/' + mac,
    ]) status(await api('GET', path), 401);
  });

  await step('ACK authentifié : config_saved, ordre applied et révision acknowledged', async () => {
    status(await device('ack', { source_rev: 2, applied: true }, wrongKey), 401);
    const r = await device('ack', { source_rev: 2, applied: true, app_version: 'workerd-fixture' });
    status(r, 200);
    assert.equal(r.data.result, 'config_saved');
    assert.equal((await db.prepare('SELECT state FROM box_orders WHERE order_id=?').bind(sourceOrder).first()).state, 'applied');
    assert.equal((await db.prepare('SELECT state FROM source_revisions WHERE mac=? AND rev=2').bind(mac).first()).state, 'acknowledged');
    status(await device('ack', { source_rev: 1, applied: true }), 409);
    status(await device('ack', { source_rev: 3, applied: true }), 409);
  });

  await step('révocation admin : accès retiré et sources absentes au poll suivant', async () => {
    const r = await api('PATCH', '/api/v1/licenses/' + licenseId, { token, body: { status: 'inactive' } });
    status(r, 200);
    const state = await device('state');
    status(state, 200);
    assert.equal(state.data.active, false);
    assert.equal(state.data.status, 'inactive');
    assert.equal(state.data.sources_ok, false);
    assert.deepEqual(state.data.sources, []);
    status(await device('ack', { source_rev: 2, applied: true }), 403);
  });

  await step('aucun hook Gold, débit ou appel HTTP externe dans tout le scénario', async () => {
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM gold_lines').first()).n, 0);
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM gold_history').first()).n, 0);
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM audit_logs WHERE action LIKE 'gold.hook.%'").first()).n, 0);
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM credit_ledger').first()).n, 0);
    assert.deepEqual(outbound, []);
  });
  await mf.dispose();
  assert.deepEqual(outbound, [], 'aucune sous-requête différée externe');
  console.log(JSON.stringify({ result: 'PASS', checks: passed, duration_ms: Date.now() - started, external_requests: outbound.length }));
} catch (e) {
  console.error('FAIL ' + currentStep + ': ' + (e?.message || String(e)));
  try { await mf.dispose(); } catch (_) {}
  process.exitCode = 1;
}
