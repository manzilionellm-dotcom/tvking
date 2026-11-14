// Intégration réelle du pont NOVATUBE 4K : Worker, routes panel et SQLite.
// Aucun service distant n'est appelé. Les clés et URL sont des fixtures.
// NOVATUBE4K_TEST_ENTRY=/chemin/novatube4k-live-entry.js permet de rejouer
// exactement les mêmes scénarios contre le bundle déployé enveloppé.
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import { createNovatube4kEntry } from './novatube4k-wrapper.js';

const moduleUrl = process.env.NOVATUBE4K_TEST_ENTRY
  ? pathToFileURL(resolve(process.env.NOVATUBE4K_TEST_ENTRY)).href
  : new URL('./novatube4k-entry.js', import.meta.url).href;
const entry = await import(moduleUrl);
const worker = entry.default;
const APP = 'app_novatube4k';
const RAW = 'A2:13:24:35:46:57';
const RAW_HEX = RAW.replaceAll(':', '');
const KEY = 'a5'.repeat(32);
const URL_A = 'https://list.example.test/a.m3u?token=fixture-only';
const URL_B = 'https://list.example.test/b.m3u';
const DAY = 86_400_000;

function fixture(t) {
  const { DB, db, faults } = createD1({
    extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'],
  });
  const env = {
    DB,
    ADMIN_SECRET: crypto.randomUUID(),
    SECRETS_KEY: crypto.randomUUID(),
    ACCOUNT_ENCRYPTION_KEY: crypto.randomUUID(),
    DEVICE_TOKEN_SECRET: crypto.randomUUID(),
    GOLD_PANEL_API_KEY: 'fixtureOnlyKeyNeverUsedOutsideTests1234',
  };
  env.RT_HUB = fakeRealtimeHub(env, entry.RealtimeHub);
  const pending = [];
  const ctx = { waitUntil(p) { pending.push(Promise.resolve(p)); }, passThroughOnException() {} };
  const outbound = [];
  t.mock.method(globalThis, 'fetch', async (input) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    outbound.push({ host: url.host, path: url.pathname });
    return new Response('{"error":"external_network_disabled_in_fixture"}', { status: 503 });
  });
  async function drain() {
    while (pending.length) await Promise.all(pending.splice(0));
  }
  async function api(method, path, { token, body, headers: extra = {} } = {}) {
    const headers = {
      'content-type': 'application/json',
      'cf-connecting-ip': '192.0.2.40',
      ...extra,
    };
    if (token) headers.authorization = `Bearer ${token}`;
    const response = await worker.fetch(new Request(`https://app.test${path}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, ctx);
    const text = await response.text();
    await drain();
    let json;
    try { json = JSON.parse(text); } catch { json = null; }
    return { status: response.status, json, headers: response.headers, text };
  }
  async function admin() {
    const r = await api('POST', '/api/v1/auth/login', {
      body: { email: 'admin', password: env.ADMIN_SECRET },
    });
    assert.equal(r.status, 200, 'login de fixture');
    assert.ok(r.json?.token, 'JWT de fixture obtenu');
    return r.json.token;
  }
  async function device(action = 'register', body = {}, key = KEY) {
    return api('POST', `/api/novatube4k/${action}`, {
      body: { raw_mac: RAW, ...body },
      headers: key ? { 'X-Device-Key': key } : {},
    });
  }
  async function registered() {
    const r = await device();
    assert.equal(r.status, 200, 'enrôlement de fixture');
    assert.match(r.json?.mac || '', /^MK(?::[0-9A-F]{2}){5}$/);
    return r.json.mac;
  }
  async function activate(token, mac, plan = 'yearly', extra = {}) {
    const r = await api('POST', '/api/v1/activate', {
      token, body: { mac, plan, ...extra },
      headers: { 'Idempotency-Key': crypto.randomUUID() },
    });
    assert.ok(r.status === 200 || r.status === 201, `activation de fixture : ${r.status}`);
    return r;
  }
  async function reseller(adminToken, permissions = ['activate', 'devices', 'sources']) {
    const email = `reseller-${crypto.randomUUID()}@example.test`;
    const password = `Fixture9Aa!${crypto.randomUUID()}`;
    const made = await api('POST', '/api/v1/resellers', {
      token: adminToken, body: { email, password, name: 'Revendeur fixture', credit_balance: 5 },
    });
    assert.equal(made.status, 201, 'création revendeur de fixture');
    const id = made.json.id;
    const patched = await api('PATCH', `/api/v1/resellers/${id}`, {
      token: adminToken, body: { permissions },
    });
    assert.equal(patched.status, 200);
    const logged = await api('POST', '/api/v1/auth/reseller/login', { body: { email, password } });
    assert.equal(logged.status, 200);
    return { id, token: logged.json.token };
  }
  t.after(async () => { await drain(); db.close(); });
  return { env, db, faults, ctx, outbound, api, admin, device, registered, activate, reseller };
}

test('enrôlement visible dans le panel, inactif et idempotent, sans essai', async (t) => {
  const f = fixture(t);
  const first = await f.device();
  assert.equal(first.status, 200);
  assert.equal(first.json.created, true);
  assert.equal(first.json.active, false);
  assert.equal(first.json.status, 'inactive');
  assert.equal(first.json.app_id, APP);
  assert.deepEqual(first.json.sources, []);
  assert.equal(first.json.sources_ok, false);
  assert.equal(first.json.expires_at, 0);
  const second = await f.device();
  assert.equal(second.status, 200);
  assert.equal(second.json.created, false);
  assert.equal(second.json.mac, first.json.mac);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM devices').get().n, 1);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM customers').get().n, 1);
  assert.deepEqual({ ...f.db.prepare('SELECT app_id, status, plan, expires_at FROM licenses').get() },
    { app_id: APP, status: 'inactive', plan: 'custom', expires_at: 0 });
  const token = await f.admin();
  const panel = await f.api('GET', `/api/v1/devices?q=${RAW_HEX}`, { token });
  assert.equal(panel.status, 200);
  const row = panel.json.items.find((d) => d.mac === first.json.mac);
  assert.ok(row, 'recherche par MAC physique dans la fiche panel');
  assert.match(row.label, /NOVATUBE/);
  assert.ok(row.label.includes(RAW_HEX));
  const online = await f.api('GET', '/api/v1/online', { token });
  assert.equal(online.status, 200);
  assert.ok(online.json.items.some((d) => d.mac === first.json.mac),
    'présence authentifiée visible dans En ligne sans heartbeat legacy');
  assert.equal(f.outbound.length, 0);
});

test('clé appareil obligatoire, clé concurrente refusée, état sans fuite de source', async (t) => {
  const f = fixture(t);
  await f.registered();
  assert.equal((await f.device('state', {}, null)).status, 401);
  assert.equal((await f.device('state', {}, 'b6'.repeat(32))).status, 401);
  const conflict = await f.device('register', {}, 'b6'.repeat(32));
  assert.equal(conflict.status, 409);
  assert.equal(conflict.json.error, 'device_key_conflict');
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM devices').get().n, 1);
});

test('activation exige toujours JWT et origine autorisée', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const body = { mac, plan: 'yearly', app_id: 'app_7motion' };
  const anon = await f.api('POST', '/api/v1/activate', { body });
  assert.ok([401, 403].includes(anon.status));
  const token = await f.admin();
  const origin = await f.api('POST', '/api/v1/activate', {
    token, body, headers: { Origin: 'https://untrusted.example.test' },
  });
  assert.equal(origin.status, 403);
  assert.equal((await f.device('state')).json.active, false);
  assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM licenses WHERE status='active'").get().n, 0);
  assert.equal(f.outbound.length, 0);
});

test('yearly et lifetime activent seulement NOVATUBE, sans hook Gold ni appel CMS', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  const configured = await f.api('POST', '/api/v1/gold/config', {
    token, body: { gold_enabled: '1', gold_trial_enabled: '1' },
  });
  assert.equal(configured.status, 200, 'Gold activé dans la fixture pour rendre une fuite observable');
  const before = Date.now();
  const yearly = await f.activate(token, mac, 'yearly', { app_id: 'app_7motion' });
  assert.ok(Math.abs(yearly.json.expires_at - before - 365 * DAY) < 10_000);
  assert.equal((await f.device('state')).json.active, true);
  const lifetime = await f.activate(token, mac, 'lifetime');
  assert.equal(lifetime.json.expires_at, null);
  assert.equal((await f.device('state')).json.plan, 'lifetime');
  assert.deepEqual(f.db.prepare('SELECT app_id, status, plan FROM licenses').all().map((r) => ({ ...r })),
    [{ app_id: APP, status: 'active', plan: 'lifetime' }]);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM gold_lines').get().n, 0);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM gold_history').get().n, 0);
  assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM audit_logs WHERE action LIKE 'gold.hook.%'").get().n, 0);
  assert.equal(f.outbound.length, 0, 'aucun appel réseau même avec Gold configuré');
});

test('Idempotency-Key et X-Request-Id traversent le pont sans double prolongation', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  const headers = { 'Idempotency-Key': crypto.randomUUID(), 'X-Request-Id': 'nova-wrapper-trace-001' };
  const body = { mac, app_id: 'app_7motion', plan: 'yearly' };
  const first = await f.api('POST', '/api/v1/activate', { token, body, headers });
  assert.equal(first.status, 201);
  const replay = await f.api('POST', '/api/v1/activate', { token, body, headers });
  assert.equal(replay.status, 201);
  assert.equal(replay.headers.get('Idempotent-Replayed'), 'true');
  assert.equal(replay.headers.get('X-Request-Id'), headers['X-Request-Id']);
  assert.equal(replay.json.license_id, first.json.license_id);
  assert.equal(replay.json.expires_at, first.json.expires_at);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM licenses').get().n, 1);
  assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM audit_logs WHERE action LIKE 'activate.%'").get().n, 1);
  const mismatch = await f.api('POST', '/api/v1/activate', {
    token, body: { ...body, plan: 'lifetime' }, headers,
  });
  assert.equal(mismatch.status, 409);
  assert.equal(mismatch.json.error, 'idempotency_mismatch');
});

test('droits revendeur, propriété de la MAC et débit unique restent appliqués', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const admin = await f.admin();
  const denied = await f.reseller(admin, ['devices', 'sources']);
  const owner = await f.reseller(admin);
  const other = await f.reseller(admin);
  const body = { mac, plan: 'yearly' };
  assert.equal((await f.api('POST', '/api/v1/activate', { token: denied.token, body })).status, 403);
  const headers = { 'Idempotency-Key': crypto.randomUUID() };
  const first = await f.api('POST', '/api/v1/activate', { token: owner.token, body, headers });
  assert.equal(first.status, 201);
  assert.equal(first.json.credits_charged, 1);
  assert.equal(first.json.credit_balance, 4);
  const replay = await f.api('POST', '/api/v1/activate', { token: owner.token, body, headers });
  assert.equal(replay.headers.get('Idempotent-Replayed'), 'true');
  assert.equal(f.db.prepare('SELECT credit_balance FROM resellers WHERE id=?').get(owner.id).credit_balance, 4);
  assert.equal(f.db.prepare('SELECT reseller_id FROM devices WHERE mac=?').get(mac).reseller_id, owner.id);
  assert.equal((await f.api('POST', '/api/v1/activate', { token: other.token, body })).status, 403);
  assert.equal((await f.api('PUT', `/api/v1/sources/${encodeURIComponent(mac)}`, {
    token: other.token, body: { sources: [{ type: 'm3u', m3u_url: URL_A }] },
  })).status, 403);
  assert.equal(f.db.prepare('SELECT credit_balance FROM resellers WHERE id=?').get(other.id).credit_balance, 5);
});

test('licence étrangère, expiration, gel, bannissement et app désactivée ne donnent aucun accès', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  const row = f.db.prepare('SELECT id, customer_id FROM devices WHERE mac=?').get(mac);
  const now = Date.now();
  f.db.prepare(`INSERT INTO apps (id,name,package_name,created_at,updated_at) VALUES (?,?,?,?,?)`)
    .run('app_fixture_other', 'Other fixture', 'example.test.other', now, now);
  f.db.prepare(`INSERT INTO licenses (id,customer_id,device_id,app_id,status,plan,started_at,expires_at,created_at,updated_at)
    VALUES (?,?,?,?,'active','lifetime',?,NULL,?,?)`)
    .run('lic_fixture_other', row.customer_id, row.id, 'app_fixture_other', now, now, now);
  assert.equal((await f.device('state')).json.active, false, 'une autre app active ne débloque pas NOVATUBE');
  await f.activate(token, mac);
  f.db.prepare('UPDATE licenses SET expires_at=? WHERE app_id=?').run(Date.now() - 1, APP);
  assert.equal((await f.device('state')).json.status, 'expired');
  f.db.prepare('UPDATE licenses SET expires_at=? WHERE app_id=?').run(Date.now() + DAY, APP);
  for (const value of ['frozen', 'banned']) {
    f.db.prepare('UPDATE devices SET block_status=? WHERE mac=?').run(value, mac);
    const state = await f.device('state');
    assert.equal(state.json.status, value);
    assert.equal(state.json.active, false);
    assert.deepEqual(state.json.sources, []);
  }
  f.db.prepare('UPDATE devices SET block_status=NULL WHERE mac=?').run(mac);
  f.db.prepare('UPDATE apps SET is_active=0 WHERE id=?').run(APP);
  const disabled = await f.device('state');
  assert.equal(disabled.json.status, 'disabled');
  assert.equal(disabled.json.active, false);
});

test('publication M3U/Xtream, source masquée, révision et ACK authentifié visibles dans le panel', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  const sources = [
    { type: 'm3u', label: 'Liste active', m3u_url: URL_A },
    { type: 'xtream', label: 'Liste masquée', server_url: 'https://xtream.example.test/prefix', username: 'fixture-u', password: 'fixture-p', enabled: false },
  ];
  const put = await f.api('PUT', `/api/v1/sources/${encodeURIComponent(mac)}`, {
    token, body: { sources }, headers: { 'X-Request-Id': 'nova-source-trace-001' },
  });
  assert.equal(put.status, 200);
  assert.equal(put.json.rev, 1);
  assert.ok(put.json.order_id);
  const inactive = await f.device('state');
  assert.equal(inactive.json.sources_ok, false);
  assert.deepEqual(inactive.json.sources, []);
  await f.activate(token, mac);
  const state = await f.device('state');
  assert.equal(state.status, 200);
  assert.equal(state.json.active, true);
  assert.equal(state.json.sources_ok, true, 'lecture interne de la MAC au bon format');
  assert.equal(state.json.source_rev, 1);
  assert.equal(state.json.sources.length, 2);
  assert.equal(state.json.sources[0].m3u_url, URL_A);
  assert.ok(state.json.sources.every((source) => typeof source.id === 'string' && source.id.length > 0),
    'chaque source dédiée fournit l’identité stable requise par syncAtlas Android');
  assert.equal(state.json.sources[1].enabled, false, 'la désactivation est transmise au contrôleur Android');
  const preAck = f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(put.json.order_id);
  assert.notEqual(preAck.state, 'applied', 'servir le JSON ne simule pas son application');
  const badKey = await f.device('ack', { source_rev: 1, applied: true }, 'b6'.repeat(32));
  assert.equal(badKey.status, 401);
  const ack = await f.device('ack', { source_rev: 1, applied: true, app_version: 'fixture-novatube' });
  assert.equal(ack.status, 200);
  assert.equal(ack.json.orders_acked, 1);
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(put.json.order_id).state, 'applied');
  assert.equal(f.db.prepare('SELECT state FROM source_revisions WHERE mac=? AND rev=1').get(mac).state, 'acknowledged');
  const again = await f.device('ack', { source_rev: 1, applied: true });
  assert.equal(again.status, 200, 'ACK répété idempotent');
  const orders = await f.api('GET', `/api/v1/orders?mac=${encodeURIComponent(mac)}`, { token });
  assert.equal(orders.status, 200);
  assert.equal(orders.json.items.find((o) => o.order_id === put.json.order_id).state, 'applied');
  assert.equal(f.outbound.length, 0, 'le Worker ne télécharge pas la playlist ni les flux');
});

test('ACK futur ou obsolète refusé, suppression finale transmise comme vraie révision vide', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  await f.activate(token, mac);
  const put = await f.api('PUT', `/api/v1/sources/${encodeURIComponent(mac)}`, {
    token, body: { sources: [{ type: 'm3u', m3u_url: URL_B }] },
  });
  assert.equal(put.status, 200);
  assert.equal((await f.device('ack', { source_rev: 1, applied: true })).status, 409, 'révision jamais servie');
  assert.equal((await f.device('state')).json.source_rev, 1);
  const removed = await f.api('DELETE', `/api/v1/sources/${encodeURIComponent(mac)}`, { token });
  assert.equal(removed.status, 200);
  assert.equal((await f.device('ack', { source_rev: 1, applied: true })).status, 409, 'ancienne révision après nouvelle publication');
  const state = await f.device('state');
  assert.equal(state.json.sources_ok, true);
  assert.deepEqual(state.json.sources, []);
  assert.equal(state.json.source_rev, 2);
  assert.equal((await f.device('ack', { source_rev: 2, applied: true })).status, 200);
});

test('anciennes routes publiques ne révèlent ni ne modifient une MAC NOVATUBE liée', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  await f.activate(token, mac);
  assert.equal((await f.api('PUT', `/api/v1/sources/${encodeURIComponent(mac)}`, {
    token, body: { sources: [{ type: 'm3u', m3u_url: URL_A }] },
  })).status, 200);
  const paths = [
    ['GET', `/api/device-source/${mac}`],
    ['GET', `/api/device-source/${encodeURIComponent(mac)}`],
    ['GET', `/api/self-source/${mac}`],
    ['POST', `/api/self-source/${mac}`, { type: 'm3u', m3u_url: URL_B }],
    ['DELETE', `/api/self-source/${mac}`],
    ['GET', `/api/status/${mac}`],
    ['GET', `/api/history/${mac}`],
    ['GET', `/api/backup/${mac}`],
    ['PUT', `/api/backup/${mac}`, { playlists: [] }],
    ['GET', `/config/${mac}`],
    ['GET', `/api/box/wait/${mac}?timeout=1`],
    ['GET', `/api/box/wait?mac=${encodeURIComponent(mac)}&timeout=1`],
    ['POST', `/api/box/ack/${mac}`, { orders: [] }],
    ['POST', `/api/box/ack?mac=${encodeURIComponent(mac)}`, { orders: [] }],
    ['GET', `/api/box/ws?mac=${encodeURIComponent(mac)}`],
    ['POST', '/api/heartbeat', { mac }],
    ['POST', '/api/blackbox', { mac, events: [] }],
    ['POST', '/api/gold-trial', { mac }],
    ['POST', '/api/v1/device/trial', { mac }],
  ];
  for (const [method, path, body] of paths) {
    const r = await f.api(method, path, { body });
    assert.ok([401, 403].includes(r.status), `${method} ${path} doit imposer le circuit appareil authentifié (${r.status})`);
    assert.equal(r.text.includes(URL_A), false);
    assert.equal(r.text.includes('fixture-only'), false);
  }
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM licenses').get().n, 1);
  const state = await f.device('state');
  assert.equal(state.json.sources_ok, true, 'la lecture interne authentifiée reste possible');
  assert.equal(state.json.sources[0].m3u_url, URL_A);
});

test('panne de liaison D1 ferme le pont au lieu de tomber sur Gold', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  f.faults.add({ match: /SELECT 1 AS found FROM novatube4k_devices/, times: 1 });
  const response = await f.api('POST', '/api/v1/activate', {
    token, body: { mac, plan: 'yearly' },
  });
  assert.equal(response.status, 503);
  assert.equal(f.db.prepare('SELECT status FROM licenses WHERE app_id=?').get(APP).status, 'inactive');
  assert.equal(f.outbound.length, 0);
});

test('corps dépassant la lecture bornée refusé sans retour vers activation ou heartbeat legacy', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const token = await f.admin();
  const largeActivation = await f.api('POST', '/api/v1/activate', {
    token,
    body: { mac, plan: 'yearly', app_id: 'app_7motion', padding: 'x'.repeat(17 * 1024) },
  });
  assert.equal(largeActivation.status, 413);
  const largeHeartbeat = await f.api('POST', '/api/heartbeat', {
    body: { mac, padding: 'x'.repeat(1024 * 1024 + 1) },
  });
  assert.equal(largeHeartbeat.status, 413);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM licenses').get().n, 1);
  assert.equal(f.db.prepare('SELECT status FROM licenses WHERE app_id=?').get(APP).status, 'inactive');
  assert.equal(f.outbound.length, 0);
});

test('variantes de MAC admises par Gold restent isolées du circuit essai', async (t) => {
  const f = fixture(t);
  const mac = await f.registered();
  const variants = [
    mac.toLowerCase(),
    mac.replaceAll(':', '-'),
    mac.replaceAll(':', '.'),
    mac.replaceAll(':', ''),
    encodeURIComponent(mac),
  ];
  for (const variant of variants) {
    for (const path of ['/api/gold-trial', '/api/v1/device/trial']) {
      const response = await f.api('POST', path, { body: { mac: variant } });
      assert.equal(response.status, 401, `${path} : ${variant}`);
      assert.equal(response.json.error, 'novatube4k_device_key_required');
    }
  }
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM licenses').get().n, 1);
  assert.equal(f.outbound.length, 0);
});

test('MAC legacy et routes hors périmètre gardent exactement la requête et la réponse historiques', async (t) => {
  const f = fixture(t);
  await f.registered();
  const seen = [];
  let sentinel;
  const legacy = {
    async fetch(request, env, ctx) { seen.push({ request, env, ctx }); return sentinel; },
    scheduled: () => 'unchanged',
  };
  const original = { async fetch() { assert.fail('le worker sans Gold ne doit pas traiter une MAC legacy'); } };
  const bridge = createNovatube4kEntry(legacy, original);
  assert.equal(bridge.scheduled, legacy.scheduled);
  const raw = ' { "mac" : "MK:AA:BB:CC:DD:99", "plan" : "yearly" } ';
  const cases = [
    new Request('https://app.test/api/v1/activate', { method: 'POST', body: raw, headers: { 'Idempotency-Key': 'fixture-idem-0001' } }),
    new Request('https://app.test/api/device-source/MK:AA:BB:CC:DD:99'),
    new Request('https://app.test/api/heartbeat', { method: 'POST', body: JSON.stringify({ mac: 'MK:AA:BB:CC:DD:99' }) }),
    new Request('https://app.test/api/v1/licenses'),
    new Request('https://app.test/royal'),
  ];
  for (const request of cases) {
    const expectedBody = await request.clone().text();
    sentinel = new Response('legacy-response', { status: 202, headers: { 'X-Legacy': 'preserved' } });
    const response = await bridge.fetch(request, f.env, f.ctx);
    assert.equal(response, sentinel);
    const called = seen.at(-1);
    assert.equal(called.request, request);
    assert.equal(await called.request.text(), expectedBody);
    assert.equal(called.env, f.env);
    assert.equal(called.ctx, f.ctx);
  }
  assert.equal(seen.length, cases.length);
});
