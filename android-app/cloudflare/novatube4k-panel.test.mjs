// Même tests contre les sources ou le bundle historique exact enveloppé.
// Tout est local : SQLite réel, Durable Object réel sur stockage de fixture,
// JWT de fixture ; chaque fetch extérieur est intercepté et refusé.
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import { sanitizeNovatubeDiagnostic } from './novatube4k-panel.js';
import { createNovatube4kEntry } from './novatube4k-wrapper.js';

const entry = await import(process.env.NOVATUBE4K_TEST_ENTRY
  ? pathToFileURL(resolve(process.env.NOVATUBE4K_TEST_ENTRY)).href
  : new URL('./novatube4k-entry.js', import.meta.url).href);
const APP = 'app_novatube4k';
const RAW = 'A2:13:24:35:46:57';
const RAW2 = 'A2:13:24:35:46:58';
const KEY = 'a5'.repeat(32);
const KEY2 = 'b6'.repeat(32);

function fixture(t) {
  const { DB, db, faults } = createD1({ extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'] });
  const env = { DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID(),
    ACCOUNT_ENCRYPTION_KEY: crypto.randomUUID(), DEVICE_TOKEN_SECRET: crypto.randomUUID(),
    GOLD_PANEL_API_KEY: 'fixtureOnlyKeyNeverUsedOutsideTests1234', DEFAULT_SERVERS: '[]' };
  env.RT_HUB = fakeRealtimeHub(env, entry.RealtimeHub);
  const pending = [], outbound = [], rooms = [];
  const hubGet = env.RT_HUB.get;
  env.RT_HUB.get = (id) => { rooms.push(id); return hubGet(id); };
  const ctx = { waitUntil(p) { pending.push(Promise.resolve(p)); }, passThroughOnException() {} };
  t.mock.method(globalThis, 'fetch', async (input) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    outbound.push({ host: url.host, path: url.pathname });
    return new Response('{"error":"fixture_no_external_network"}', { status: 503 });
  });
  async function drain() { while (pending.length) await Promise.all(pending.splice(0)); }
  async function api(method, path, { token, body, text, headers = {} } = {}) {
    const h = { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.48', 'cf-ipcountry': 'FR', ...headers };
    if (token) h.authorization = 'Bearer ' + token;
    const response = await entry.default.fetch(new Request('https://fixture.test' + path, {
      method, headers: h, body: text ?? (body === undefined ? undefined : JSON.stringify(body)),
    }), env, ctx);
    const raw = await response.text();
    await drain();
    let json;
    try { json = JSON.parse(raw); } catch { json = null; }
    return { status: response.status, json, raw, headers: response.headers };
  }
  async function device(action = 'register', body = {}, key = KEY, raw = RAW) {
    return api('POST', '/api/novatube4k/' + action, {
      body: { raw_mac: raw, ...body }, headers: key ? { 'X-Device-Key': key } : {},
    });
  }
  async function register(raw = RAW, key = KEY) {
    const r = await device('register', {}, key, raw);
    assert.equal(r.status, 200, 'fixture register');
    return r.json.mac;
  }
  async function admin() {
    const r = await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: env.ADMIN_SECRET } });
    assert.equal(r.status, 200);
    return r.json.token;
  }
  async function activate(token, mac) {
    const r = await api('POST', '/api/v1/activate', { token, body: { mac, plan: 'yearly' } });
    assert.equal(r.status, 201);
    return r.json;
  }
  async function source(token, mac, label = 'Liste fixture') {
    const r = await api('PUT', '/api/v1/sources/' + encodeURIComponent(mac), {
      token, body: { sources: [{ type: 'm3u', label, m3u_url: 'https://fixture.test/playlist.m3u?token=fixture-secret' }] },
      headers: { 'X-Request-Id': 'novatube-panel-fixture-source' },
    });
    assert.equal(r.status, 200);
    return r.json;
  }
  async function reseller(adminToken, permissions = ['activate', 'devices', 'sources']) {
    const email = crypto.randomUUID() + '@example.test', password = 'Fixture9Aa!' + crypto.randomUUID();
    const made = await api('POST', '/api/v1/resellers', { token: adminToken,
      body: { email, password, name: 'Fixture', credit_balance: 5 } });
    assert.equal(made.status, 201);
    assert.equal((await api('PATCH', '/api/v1/resellers/' + made.json.id,
      { token: adminToken, body: { permissions } })).status, 200);
    const login = await api('POST', '/api/v1/auth/reseller/login', { body: { email, password } });
    assert.equal(login.status, 200);
    return { id: made.json.id, token: login.json.token };
  }
  t.after(async () => { await drain(); assert.equal(outbound.length, 0, 'zéro appel extérieur'); db.close(); });
  return { env, db, faults, ctx, outbound, rooms, api, device, register, admin, activate, source, reseller, drain };
}

test('toutes les routes appareil exigent la clé et une identité existante', async (t) => {
  const f = fixture(t);
  const actions = ['panel', 'blackbox', 'orders-ack', 'wait', 'rt-ticket', 'history', 'backup', 'feedback'];
  for (const action of actions) assert.equal((await f.device(action)).status, 401, action + ' inconnu');
  await f.register();
  for (const action of actions) {
    assert.equal((await f.device(action, {}, null)).status, 401, action + ' sans clé');
    assert.equal((await f.device(action, {}, KEY2)).status, 401, action + ' mauvaise clé');
  }
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM licenses').get().n, 1);
});

test('inventaire et présence réels : inconnus null, aucun compte fournisseur, historique vidé', async (t) => {
  const f = fixture(t), mac = await f.register();
  // La télémétrie doit aussi fonctionner après désactivation d'un essai.
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE app_id=?").run(APP);
  const r = await f.device('panel', { model: 'Fixture TV', android: '6.0', build: 'build fixture',
    appBuild: Math.floor(Date.now() / 1000), appVersion: '334.2.fixture', channel: 'Information', quality: null,
    sources: [{ type: 'm3u', name: 'Liste Atlas M3U', server: 'https://fixture-user:fixture-pass@provider.test/p?token=secret',
      username: 'must-not-store', password: 'must-not-store', active: true }], recent: ['channel1', 'https://secret.test/u/p/1'] });
  assert.equal(r.status, 200); assert.equal(r.json.telemetry_ok, true);
  const row = f.db.prepare('SELECT * FROM devices WHERE mac=?').get(mac);
  const inventory = JSON.parse(row.local_sources_json);
  assert.equal(inventory[0].channels, null); assert.equal(inventory[0].username, '');
  assert.equal(inventory[0].server, 'https://provider.test');
  assert.equal(row.app_version, '334.2.fixture');
  assert.deepEqual(JSON.parse(row.recent_json), ['channel1']);
  assert.deepEqual({ ...f.db.prepare('SELECT channel,quality FROM presence WHERE mac=?').get(mac) }, { channel: 'Information', quality: null });
  await f.device('state');
  assert.equal(f.db.prepare('SELECT channel FROM presence WHERE mac=?').get(mac).channel, 'Information');
  const cleared = await f.device('panel', { sources: [], recent: [] });
  assert.equal(cleared.json.telemetry_ok, true);
  assert.equal(f.db.prepare('SELECT local_sources_json FROM devices WHERE mac=?').get(mac).local_sources_json, '[]');
  assert.equal(f.db.prepare('SELECT recent_json FROM devices WHERE mac=?').get(mac).recent_json, '[]');
  assert.equal((await f.device('state')).json.active, false, 'présence sans essai');
});

test('panne de présence ou inventaire signalée sans confirmation mensongère', async (t) => {
  const f = fixture(t); await f.register(); await f.device('panel');
  f.faults.add({ match: /UPDATE devices SET local_sources_json = \? WHERE id/, times: 1 });
  const r = await f.device('panel', { sources: [{ type: 'm3u' }] });
  assert.equal(r.status, 200); assert.equal(r.json.telemetry_ok, false);
  assert.equal(r.json.commands_ok, true);
});

test('configuration réelle, portée plateforme, etag et URL APK dédiée sans annoncer de build Flutter', async (t) => {
  const f = fixture(t); await f.register(); const token = await f.admin();
  assert.equal((await f.api('PUT', '/api/v1/theme?platform=tv', { token,
    body: { appName: 'Nom historique', accent: '#123456', bg: 'dark' } })).status, 200);
  const r = await f.device('panel', { appBuild: Math.floor(Date.now() / 1000), platform: 'tv' });
  assert.equal(r.status, 200); assert.deepEqual(r.json.config_errors, []);
  assert.equal(r.json.config_scope, 'platform');
  assert.equal(r.json.config.theme.accent, '#123456');
  assert.equal(r.json.config.theme.appName, 'Nom historique');
  assert.equal(r.json.config.app_version.download_url, 'https://novatube4k-apk.vercel.app/');
  assert.equal(Number(r.json.config.app_version.latestBuildTs || 0), 0);
  assert.deepEqual(Object.keys(r.json.config).sort(), ['ad','announcements','app_version','featured','feedback','home','pricing','servers','theme']);
  const cached = await f.device('panel', { config_etag: r.json.config_etag });
  assert.equal(cached.json.config_unchanged, true); assert.equal(cached.json.config, undefined);
  assert.equal((await f.api('PUT', '/api/v1/theme?platform=tv', { token,
    body: { appName: '', accent: '', bg: '' } })).status, 200);
  const disabled = await f.device('panel', { config_etag: r.json.config_etag });
  assert.equal(disabled.json.config_unchanged, false); assert.equal(disabled.json.config.theme.accent, '');
});

test('réveil global limité aux NOVATUBE récentes et aux mutations réussies', async (t) => {
  const f = fixture(t), mac = await f.register(), offline = await f.register(RAW2, KEY2), token = await f.admin();
  f.db.prepare('UPDATE devices SET last_seen_at=1 WHERE mac=?').run(offline);
  f.rooms.length = 0;
  const forbidden = await f.api('POST', '/api/v1/featured', { body: { name: 'fixture' } });
  assert.equal(forbidden.status, 401); assert.deepEqual(f.rooms, []);
  const invalid = await f.api('PUT', '/api/v1/theme?platform=tv', { token, body: { accent: 'invalid' } });
  assert.equal(invalid.status, 400); assert.deepEqual(f.rooms, []);
  assert.equal((await f.api('POST', '/api/v1/featured', { token, body: { name: 'Événement fixture', note: 'Texte fixture' } })).status, 200);
  assert.ok(f.rooms.includes(mac)); assert.ok(!f.rooms.includes(offline));
  const wait = await f.device('wait', { after: 0, timeout: 200 });
  assert.equal(wait.status, 200); assert.ok(wait.json.events.some((event) => event.type === 'featured' && event.mac === mac));
  assert.ok(!wait.raw.includes('fixture.test'));
});

test('boîte noire : demande panel réveillée, filtrage, stockage et lecture par MAC', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  const ask = await f.api('POST', '/api/v1/blackbox/' + encodeURIComponent(mac) + '/ask', { token, body: {} });
  assert.equal(ask.status, 200);
  const wait = await f.device('wait', { after: 0, timeout: 200 });
  assert.equal(wait.json.timeout, false);
  const state = await f.device('state'); assert.equal(state.json.blackbox_pull, ask.json.requested_at);
  const diagnostic = 'LECTEUR READY\nhttps://provider.test/user/pass/42.ts?secret=fixture\nX-Device-Key=' + KEY
    + '\nraw_mac=' + RAW + '\npassword=fixture-password user=fixture-user';
  const sent = await f.device('blackbox', { text: diagnostic, mac: 'MK:11:22:33:44:55' });
  assert.equal(sent.status, 200); assert.equal(sent.json.ok, true); assert.ok(sent.json.updated_at > 0);
  const journal = await f.api('GET', '/api/v1/blackbox/' + encodeURIComponent(mac), { token });
  assert.equal(journal.status, 200); assert.ok(journal.json.text.includes('LECTEUR READY'));
  for (const forbidden of [KEY, RAW, 'provider.test', 'fixture-password', 'fixture-user']) assert.ok(!journal.raw.includes(forbidden), forbidden);
  assert.equal((await f.api('POST', '/api/blackbox', { body: { mac, text: 'usurpation' } })).status, 401);
});

test('boîte noire bornée, vide sans faux timestamp, caractères et identités filtrés', async (t) => {
  const f = fixture(t); await f.register();
  assert.equal((await f.device('blackbox', { text: 'x'.repeat(270000) })).status, 413);
  const empty = await f.device('blackbox', { text: '' });
  assert.equal(empty.status, 200); assert.equal(empty.json.skipped, true);
  const safe = sanitizeNovatubeDiagnostic('A21324354657 a2:13:24:35:46:57 deviceKey=' + KEY, 'A21324354657');
  assert.ok(!safe.includes(KEY)); assert.ok(!safe.includes('A21324354657')); assert.ok(!safe.includes('a2:13:24:35:46:57'));
});

test('ordres : livraison propre, reçu puis appliqué, ordre étranger et non servi refusés', async (t) => {
  const f = fixture(t), mac = await f.register(), second = await f.register(RAW2, KEY2), token = await f.admin();
  await f.activate(token, mac);
  const order = f.db.prepare("SELECT order_id FROM box_orders WHERE mac=? AND kind IN ('activate','renew')").get(mac);
  assert.ok(order);
  const premature = await f.device('orders-ack', { orders: [{ order_id: order.order_id, state: 'applied' }] });
  assert.equal(premature.json.results[0].status, 404);
  const poll = await f.device('panel');
  assert.ok(poll.json.commands.some((command) => command.order_id === order.order_id));
  const wrong = await f.device('orders-ack', { orders: [{ order_id: order.order_id, state: 'applied' }] }, KEY2, RAW2);
  assert.equal(wrong.json.results[0].status, 404);
  const received = await f.device('orders-ack', { orders: [{ order_id: order.order_id, state: 'received', received_at: Date.now() }] });
  assert.equal(received.json.results[0].status, 200);
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(order.order_id).state, 'received');
  const applied = await f.device('orders-ack', { orders: [{ order_id: order.order_id, state: 'applied', applied_at: Date.now(), result: 'license_synced' }] });
  assert.equal(applied.json.results[0].status, 200);
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(order.order_id).state, 'applied');
  assert.ok(!(await f.device('panel')).json.commands.some((command) => command.order_id === order.order_id));
  assert.ok(second !== mac);
});

test('ACK partiel, source nécessite le vrai ACK de révision, unsupported enregistré failed', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  await f.activate(token, mac); const pushed = await f.source(token, mac);
  await f.device('panel');
  const result = await f.device('orders-ack', { orders: [
    { order_id: pushed.order_id, state: 'applied' }, { order_id: 'invalid', state: 'applied' },
  ] });
  assert.equal(result.status, 200); assert.deepEqual(result.json.results.map((row) => row.status), [409, 400]);
  assert.notEqual(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(pushed.order_id).state, 'applied');
  const state = await f.device('state');
  assert.equal((await f.device('ack', { source_rev: state.json.source_rev, applied: true })).status, 200);
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(pushed.order_id).state, 'applied');
  const id = 'ord_' + crypto.randomUUID();
  f.db.prepare("INSERT INTO box_orders (order_id,mac,kind,state,created_at,updated_at) VALUES (?,?,'home','created',?,?)")
    .run(id, mac, Date.now(), Date.now());
  await f.device('panel');
  const failed = await f.device('orders-ack', { orders: [{ order_id: id, state: 'failed', error_code: 'unsupported', error_message: 'Home non compatible' }] });
  assert.equal(failed.json.results[0].status, 200);
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(id).state, 'failed');
});

test('vieux ordres source sans ACK ne masquent pas une révocation récente', async (t) => {
  const f = fixture(t), mac = await f.register(); await f.device('panel');
  const now = Date.now();
  const insert = f.db.prepare('INSERT INTO box_orders (order_id,mac,kind,state,created_at,updated_at) VALUES (?,?,?,?,?,?)');
  for (let i = 0; i < 55; i++) insert.run('ord_' + crypto.randomUUID(), mac, 'source', 'expired', now - 10000 - i, now - 10000 - i);
  const revoke = 'ord_' + crypto.randomUUID(); insert.run(revoke, mac, 'suspend', 'created', now, now);
  const r = await f.device('panel');
  assert.equal(r.json.commands.length, 50); assert.equal(r.json.commands[0].order_id, revoke);
  assert.equal(r.json.commands[0].state, 'sent');
});

test('wait utilise la MAC de clé seulement, bornes et arrêt RT explicites', async (t) => {
  const f = fixture(t), mac = await f.register();
  f.rooms.length = 0;
  const r = await f.device('wait', { timeout: 200, mac: 'MK:11:22:33:44:55' });
  assert.equal(r.status, 200); assert.equal(r.json.timeout, true); assert.deepEqual(f.rooms, [mac]);
  f.env.REALTIME_PUSH_OFF = '1';
  assert.equal((await f.device('wait', { timeout: 200 })).status, 503);
  assert.equal((await f.device('rt-ticket')).status, 503);
});

test('feedback imposé à la MAC authentifiée, notes valides et route publique fermée', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  assert.equal((await f.device('feedback', { rating: 9, message: 'fixture' })).status, 400);
  const r = await f.device('feedback', { mac: 'MK:11:22:33:44:55', rating: 4, message: 'Lecteur fluide https://private.test/secret' });
  assert.equal(r.status, 200);
  const rows = f.db.prepare('SELECT mac,rating,message FROM feedback').all();
  assert.equal(rows.length, 1); assert.equal(rows[0].mac, mac); assert.equal(rows[0].rating, 4);
  assert.ok(!rows[0].message.includes('private.test'));
  assert.equal((await f.api('GET', '/api/v1/feedback', { token })).status, 200);
  assert.equal((await f.api('POST', '/api/feedback', { body: { mac, rating: 5, message: 'spoof' } })).status, 401);
});

test('historique et sauvegarde sous licence, clé exclue, données limitées à l’appareil', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE app_id=?").run(APP);
  assert.equal((await f.device('history')).status, 403);
  assert.equal((await f.device('backup', { op: 'get' })).status, 403);
  await f.activate(token, mac);
  await f.device('panel', { recent: ['canal-1', 'canal-2'] });
  assert.deepEqual((await f.device('history')).json.recent, ['canal-1', 'canal-2']);
  assert.equal((await f.device('backup', { op: 'put', data: { nested: { deviceKey: KEY } } })).status, 400);
  const data = { favorites: ['canal-1'], recent: ['canal-2'] };
  assert.equal((await f.device('backup', { op: 'put', data, mac: 'MK:11:22:33:44:55' })).status, 200);
  assert.deepEqual((await f.device('backup', { op: 'get' })).json.data, data);
  const row = f.db.prepare('SELECT mac,data_json FROM device_backups').get();
  assert.equal(row.mac, mac); assert.ok(!row.data_json.includes(KEY));
  assert.equal((await f.api('GET', '/api/backup/' + mac)).status, 401);
});

test('reset panel expose le timestamp exact sans effacer clé ni licence', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  await f.activate(token, mac); await f.source(token, mac);
  const before = f.db.prepare('SELECT device_key_hash FROM novatube4k_devices WHERE mac=?').get(mac).device_key_hash;
  const reset = await f.api('POST', '/api/v1/sources/' + encodeURIComponent(mac) + '/reset', { token, body: {} });
  assert.equal(reset.status, 200);
  const state = await f.device('state');
  assert.equal(state.json.active, true); assert.ok(state.json.reset_at > 0);
  const panel = await f.device('panel');
  assert.equal(panel.json.reset_at, state.json.reset_at);
  assert.ok(panel.json.commands.some((command) => command.kind === 'reset'));
  assert.equal(f.db.prepare('SELECT device_key_hash FROM novatube4k_devices WHERE mac=?').get(mac).device_key_hash, before);
});

test('Analyses exige l’auth exacte et le rôle owner, exclut les essais gratuits des ventes', async (t) => {
  const f = fixture(t); await f.register();
  assert.equal((await f.api('GET', '/api/v1/insights')).status, 401);
  assert.equal((await f.api('GET', '/api/v1/insights', { token: 'invalid' })).status, 401);
  const token = await f.admin();
  assert.equal((await f.api('GET', '/api/v1/insights', { token, headers: { Origin: 'https://bad-origin.test' } })).status, 403);
  const reseller = await f.reseller(token);
  assert.equal((await f.api('GET', '/api/v1/insights', { token: reseller.token })).status, 403);
  await f.device('panel');
  const r = await f.api('GET', '/api/v1/insights', { token });
  assert.equal(r.status, 200); assert.ok(r.headers.get('cache-control').includes('no-store'));
  assert.equal(r.json.money.newPaid30, 0); assert.equal(r.json.money.paidExpired, 0);
});

test('transfert NOVATUBE : temps, clé et identité conservés, source et suivi déplacés sans crédit', async (t) => {
  const f = fixture(t), oldMac = await f.register(), newMac = await f.register(RAW2, KEY2), token = await f.admin();
  const activation = await f.activate(token, oldMac); await f.source(token, oldMac);
  const identities = f.db.prepare('SELECT raw_mac,mac,device_id,device_key_hash FROM novatube4k_devices ORDER BY raw_mac').all();
  const moved = await f.api('POST', '/api/v1/transfer', { token, body: { old_mac: oldMac, new_mac: newMac } });
  assert.equal(moved.status, 200); assert.equal(moved.json.moved_licenses, 1);
  assert.deepEqual(f.db.prepare('SELECT raw_mac,mac,device_id,device_key_hash FROM novatube4k_devices ORDER BY raw_mac').all(), identities);
  assert.equal((await f.device('state')).json.active, false);
  const destination = await f.device('state', {}, KEY2, RAW2);
  assert.equal(destination.json.active, true); assert.equal(destination.json.expires_at, activation.expires_at);
  assert.equal(destination.json.sources.length, 1); assert.ok(destination.json.source_rev > 0);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM credit_ledger').get().n, 0);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM licenses').get().n, 1);
  assert.equal(f.db.prepare("SELECT COUNT(*) n FROM audit_logs WHERE action='device.transfer'").get().n, 1);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM novatube4k_transfer_guard').get().n, 0);
  assert.equal(f.db.prepare("SELECT COUNT(*) n FROM box_orders WHERE kind='transfer'").get().n, 2);
  const replay = await f.api('POST', '/api/v1/transfer', { token, body: { old_mac: oldMac, new_mac: newMac } });
  assert.equal(replay.status, 409); assert.equal((await f.device('state', {}, KEY2, RAW2)).json.active, true);
});

test('transfert : auth/origine/permissions/ownership et destination payée fermés', async (t) => {
  const f = fixture(t), oldMac = await f.register(), newMac = await f.register(RAW2, KEY2), token = await f.admin();
  await f.activate(token, oldMac);
  const body = { old_mac: oldMac, new_mac: newMac };
  assert.equal((await f.api('POST', '/api/v1/transfer', { body })).status, 401);
  assert.equal((await f.api('POST', '/api/v1/transfer', { token, body, headers: { Origin: 'https://bad-origin.test' } })).status, 403);
  const noPermission = await f.reseller(token, ['devices']);
  assert.equal((await f.api('POST', '/api/v1/transfer', { token: noPermission.token, body })).status, 403);
  const owner = await f.reseller(token), stranger = await f.reseller(token);
  f.db.prepare('UPDATE devices SET reseller_id=? WHERE mac=?').run(owner.id, oldMac);
  assert.equal((await f.api('POST', '/api/v1/transfer', { token: stranger.token, body })).status, 403);
  await f.activate(token, newMac);
  assert.equal((await f.api('POST', '/api/v1/transfer', { token, body })).status, 409);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM licenses').get().n, 2);
});

test('transfert : autre app refusée et panne audit annule licence, sources et identité ensemble', async (t) => {
  const f = fixture(t), oldMac = await f.register(), newMac = await f.register(RAW2, KEY2), token = await f.admin();
  await f.activate(token, oldMac); await f.source(token, oldMac); await f.source(token, newMac, 'Destination fixture');
  const body = { old_mac: oldMac, new_mac: newMac };
  const dev = f.db.prepare('SELECT * FROM devices WHERE mac=?').get(newMac);
  const now = Date.now();
  f.db.prepare(`INSERT INTO licenses (id,customer_id,device_id,app_id,status,plan,started_at,expires_at,created_at,updated_at)
    VALUES ('foreign',?,?, 'app_7motion','active','lifetime',?,NULL,?,?)`).run(dev.customer_id, dev.id, now, now, now);
  assert.equal((await f.api('POST', '/api/v1/transfer', { token, body })).status, 409);
  f.db.prepare("DELETE FROM licenses WHERE id='foreign'").run();
  const licenses = f.db.prepare('SELECT * FROM licenses ORDER BY id').all();
  const sources = f.db.prepare('SELECT * FROM device_sources ORDER BY mac').all();
  const devices = f.db.prepare('SELECT id,customer_id,reseller_id,block_status FROM devices ORDER BY id').all();
  f.faults.add({ match: /INSERT INTO audit_logs[\s\S]*'device.transfer'/, times: 1 });
  const failed = await f.api('POST', '/api/v1/transfer', { token, body });
  assert.equal(failed.status, 503);
  assert.deepEqual(f.db.prepare('SELECT * FROM licenses ORDER BY id').all(), licenses);
  assert.deepEqual(f.db.prepare('SELECT * FROM device_sources ORDER BY mac').all(), sources);
  assert.deepEqual(f.db.prepare('SELECT id,customer_id,reseller_id,block_status FROM devices ORDER BY id').all(), devices);
  assert.equal((await f.device('state')).json.active, true);
  assert.equal((await f.device('state', {}, KEY2, RAW2)).json.plan, 'trial10');
});

test('transfert : activation concurrente détectée dans le lot, sans écraser la destination', async (t) => {
  const f = fixture(t), oldMac = await f.register(), newMac = await f.register(RAW2, KEY2), token = await f.admin();
  await f.activate(token, oldMac);
  const originalBatch = f.env.DB.batch.bind(f.env.DB);
  let raced = false;
  t.mock.method(f.env.DB, 'batch', async (statements) => {
    if (!raced && statements[0]?.sql.startsWith('INSERT INTO novatube4k_transfer_guard')) {
      raced = true;
      f.db.prepare("UPDATE licenses SET status='active',plan='lifetime',expires_at=NULL,updated_at=updated_at+1 WHERE device_id=(SELECT id FROM devices WHERE mac=?)").run(newMac);
    }
    return originalBatch(statements);
  });
  const r = await f.api('POST', '/api/v1/transfer', { token, body: { old_mac: oldMac, new_mac: newMac } });
  assert.equal(r.status, 409); assert.equal(r.json.error, 'transfer_conflict'); assert.equal(raced, true);
  assert.equal((await f.device('state')).json.active, true);
  const destination = await f.device('state', {}, KEY2, RAW2);
  assert.equal(destination.json.plan, 'lifetime'); assert.equal(destination.json.expires_at, null);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM licenses').get().n, 2);
});

test('essai manuel : aucune création, payé refusé, essai accordé/expiré prolongé avec journal', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  // Le refus vise une inscription inactive, pas le nouvel essai automatique.
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE app_id=?").run(APP);
  const body = { mac, days: 3 };
  assert.equal((await f.api('POST', '/api/v1/trial-extend', { body })).status, 401);
  assert.equal((await f.api('POST', '/api/v1/trial-extend', { token, body })).status, 409);
  await f.activate(token, mac);
  const paid = f.db.prepare('SELECT * FROM licenses').get();
  assert.equal((await f.api('POST', '/api/v1/trial-extend', { token, body })).status, 409);
  assert.deepEqual(f.db.prepare('SELECT * FROM licenses').get(), paid);
  const before = Date.now() + 86_400_000;
  f.db.prepare("UPDATE licenses SET plan='trial7',expires_at=?").run(before);
  const extended = await f.api('POST', '/api/v1/trial-extend', { token, body });
  assert.equal(extended.status, 200); assert.equal(extended.json.previous_until, before);
  assert.equal(extended.json.trial_until, before + 3 * 86_400_000);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM trial_extensions').get().n, 1);
  f.db.prepare("UPDATE licenses SET status='expired',expires_at=?").run(Date.now() - 86_400_000);
  const start = Date.now();
  const expired = await f.api('POST', '/api/v1/trial-extend', { token, body });
  assert.equal(expired.status, 200); assert.ok(expired.json.trial_until >= start + 3 * 86_400_000);
  assert.equal((await f.device('state')).json.active, true);
});

test('essai manuel : rôle et origine préservés, secret admin historique admis, panne annule tout', async (t) => {
  const f = fixture(t), mac = await f.register(), token = await f.admin();
  const ownerless = await f.reseller(token);
  const before = Date.now() + 86_400_000;
  f.db.prepare("UPDATE licenses SET status='active',plan='trial7',expires_at=?").run(before);
  const body = { mac, days: 2 };
  assert.equal((await f.api('POST', '/api/v1/trial-extend', { token: ownerless.token, body })).status, 403);
  assert.equal((await f.api('POST', '/api/v1/trial-extend', { body,
    headers: { 'X-Admin-Secret': f.env.ADMIN_SECRET, Origin: 'https://bad-origin.test' } })).status, 403);
  const secret = await f.api('POST', '/api/v1/trial-extend', { body, headers: { 'X-Admin-Secret': f.env.ADMIN_SECRET } });
  assert.equal(secret.status, 200); assert.equal(secret.json.trial_until, before + 2 * 86_400_000);
  const license = f.db.prepare('SELECT * FROM licenses').get();
  f.faults.add({ match: /INSERT INTO trial_extensions/, times: 1 });
  assert.equal((await f.api('POST', '/api/v1/trial-extend', { token, body })).status, 503);
  assert.deepEqual(f.db.prepare('SELECT * FROM licenses').get(), license);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM trial_extensions').get().n, 1);
});

test('grant-trial-all garde sa portée historique et ne réactive pas une inscription désactivée', async (t) => {
  const f = fixture(t), mac = await f.register(), second = await f.register(RAW2, KEY2), token = await f.admin();
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE device_id=(SELECT id FROM devices WHERE mac=?)").run(second);
  await f.activate(token, mac);
  f.db.prepare('UPDATE licenses SET expires_at=? WHERE device_id=(SELECT id FROM devices WHERE mac=?)')
    .run(Date.now() + 86_400_000, mac);
  const before = Date.now();
  const r = await f.api('POST', '/api/v1/grant-trial-all', { token, body: { days: 7 } });
  assert.equal(r.status, 200); assert.equal(r.json.updated, 1);
  assert.ok((await f.device('state')).json.expires_at >= before + 7 * 86_400_000);
  const inactive = await f.device('state', {}, KEY2, RAW2);
  assert.equal(inactive.json.active, false); assert.equal(inactive.json.expires_at, 0);
  assert.ok(second !== mac);
});

test('transfert et essais d’anciennes MAC conservent exactement requête et réponse legacy', async () => {
  const { DB, db } = createD1();
  try {
    for (const [path, body] of [
      ['/api/v1/transfer', { old_mac: 'MK:11:22:33:44:55', new_mac: 'MK:11:22:33:44:56' }],
      ['/api/v1/trial-extend', { mac: 'MK:11:22:33:44:55', days: 7 }],
    ]) {
      const request = new Request('https://fixture.test' + path, { method: 'POST', body: JSON.stringify(body) });
      const expected = new Response('fixture-legacy', { status: 202 });
      let seen;
      const legacy = { async fetch(actual) { seen = actual; assert.deepEqual(await actual.json(), body); return expected; } };
      const worker = createNovatube4kEntry(legacy, { fetch() { throw new Error('unexpected original call'); } });
      const r = await worker.fetch(request, { DB }, { waitUntil(p) { void p; } });
      assert.equal(seen, request); assert.equal(r, expected);
    }
  } finally { db.close(); }
});
