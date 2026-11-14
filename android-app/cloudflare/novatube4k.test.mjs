// Contrat NOVATUBE sur SQLite réel, via le harnais D1 transactionnel du dépôt.
// Aucune requête réseau et aucune base de production. Les pannes et courses
// sont injectées uniquement dans la base en mémoire de chaque test.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createD1 } from './test_support/d1_sqlite.mjs';
import { ensureOrderTables, createOrder, recordAck, markRevisionAck } from './box_orders.js';
import { sealSource } from './secret_box.js';
import worker from './worker.js';
import {
  handleNovatube4k, isNovatube4kMac, novatube4kAtlasMac,
  normalizeNovatube4kRawMac, NOVATUBE4K_APP_ID, NOVATUBE4K_PACKAGE,
} from './novatube4k.js';

const RAW = '123456789ABC';
const KEY = '19'.repeat(32);
const OTHER_KEY = '81'.repeat(32);
const ctx = { waitUntil() {}, passThroughOnException() {} };

function fixture(t, options = {}) {
  const f = createD1(options);
  t.after(() => f.db.close());
  f.env = { DB: f.DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() };
  f.calls = { sources: 0, limits: 0 };
  f.deps = {
    async rateLimitOk(env, request, bucket, limit, window) {
      assert.equal(env, f.env);
      assert.equal(bucket, 'novatube4k');
      assert.equal(limit, 240);
      assert.equal(window, 60000);
      f.calls.limits++;
      return true;
    },
    async readSources(mac) {
      f.calls.sources++;
      return worker.fetch(new Request('https://fixture.test/api/device-source/' + mac), f.env, ctx);
    },
    recordAck, markRevisionAck,
  };
  return f;
}

async function call(f, action, body = { raw_mac: RAW }, options = {}) {
  const request = new Request('https://fixture.test/api/novatube4k/' + action, {
    method: options.method || 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Device-Key': options.key ?? KEY, ...options.headers },
    body: options.method === 'GET' ? undefined : options.text ?? JSON.stringify(body),
  });
  const response = await handleNovatube4k(request, f.env, { ...f.deps, ...options.deps });
  if (!response) return null;
  return { status: response.status, body: await response.json(), headers: response.headers };
}

function count(f, table) {
  return f.db.prepare('SELECT COUNT(*) AS n FROM ' + table).get().n;
}

function license(f) {
  return f.db.prepare('SELECT * FROM licenses WHERE app_id = ?').get(NOVATUBE4K_APP_ID);
}

function activate(f, expiry = Date.now() + 86_400_000) {
  f.db.prepare("UPDATE licenses SET status='active', plan=?, expires_at=? WHERE app_id=?")
    .run(expiry === null ? 'lifetime' : 'yearly', expiry, NOVATUBE4K_APP_ID);
}

async function publish(f, mac, rev, sources = []) {
  await ensureOrderTables(f.env);
  f.db.prepare(`INSERT INTO source_revisions
    (mac, rev, state, panel_json, item_count, published_at, created_at)
    VALUES (?, ?, 'published', '[]', ?, ?, ?)`).run(mac, rev, sources.length, Date.now(), Date.now());
  f.db.exec(`CREATE TABLE IF NOT EXISTS device_sources (
    mac TEXT PRIMARY KEY, type TEXT NOT NULL, label TEXT, server_url TEXT,
    username TEXT, password TEXT, m3u_url TEXT, epg_url TEXT,
    sources_json TEXT, updated_at INTEGER NOT NULL)`);
  if (!sources.length) {
    // Le store de production supprime la ligne lors d'un effacement total.
    f.db.prepare('DELETE FROM device_sources WHERE mac=?').run(mac);
    return createOrder(f.env, { mac, kind: 'source_clear', configRev: rev });
  }
  const encrypted = [];
  for (const source of sources) encrypted.push(await sealSource(f.env, source));
  const first = encrypted[0] || { type: 'm3u' };
  f.db.prepare(`INSERT INTO device_sources
    (mac,type,label,server_url,username,password,m3u_url,epg_url,sources_json,updated_at)
    VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(mac) DO UPDATE SET
    sources_json=excluded.sources_json, updated_at=excluded.updated_at`)
    .run(mac, first.type, first.label || null, first.server_url || null,
      first.username || null, first.password || null, first.m3u_url || null,
      first.epg_url || null, JSON.stringify(encrypted), Date.now());
  return createOrder(f.env, { mac, kind: sources.length ? 'source' : 'source_clear', configRev: rev });
}

test('MAC brute canonique et identité Atlas déterministe sans changer le format MK', async () => {
  for (const input of [RAW, RAW.toLowerCase(), '12:34:56:78:9a:bc', '1234.5678.9abc', '12-34-56-78-9A-BC']) {
    assert.equal(normalizeNovatube4kRawMac(input), RAW);
    assert.equal(await novatube4kAtlasMac(input), await novatube4kAtlasMac(RAW));
  }
  for (const input of [null, 123, {}, 'MK:12:34:56:78:90', '12345', '123456789ABG', 'xx123456789ABC']) {
    assert.equal(normalizeNovatube4kRawMac(input), null);
  }
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('novatube4k:' + RAW)));
  const expected = 'MK:' + Array.from(bytes.slice(0, 5), (x) => x.toString(16).padStart(2, '0').toUpperCase()).join(':');
  assert.equal(await novatube4kAtlasMac(RAW), expected);
  assert.match(expected, /^MK(?::[0-9A-F]{2}){5}$/);
  assert.notEqual(await novatube4kAtlasMac('123456789ABD'), expected);
});

test('premier enrôlement atomique : visible, essai dix jours, aucune source préremplie ni débit', async (t) => {
  const f = fixture(t);
  const customersBefore = count(f, 'customers');
  const r = await call(f, 'register');
  assert.equal(r.status, 200);
  assert.equal(r.body.created, true);
  assert.equal(r.body.registered, true);
  assert.equal(r.body.active, true);
  assert.equal(r.body.status, 'active');
  assert.equal(r.body.plan, 'trial10');
  assert.equal(r.body.expires_at - r.body.trial.started_at, 10 * 86400000);
  assert.deepEqual(r.body.sources, []);
  assert.equal(r.body.sources_ok, true);
  assert.equal(f.calls.sources, 1);
  assert.equal(count(f, 'customers'), customersBefore + 1);
  assert.equal(count(f, 'devices'), 1);
  assert.equal(count(f, 'licenses'), 1);
  assert.equal(count(f, 'novatube4k_devices'), 1);
  assert.equal(license(f).status, 'active');
  assert.equal(count(f, 'credit_ledger'), 0);
  assert.equal(f.db.prepare("SELECT name FROM sqlite_master WHERE name='trial_anchors'").get(), undefined);
  const row = f.db.prepare('SELECT * FROM novatube4k_devices').get();
  assert.equal(row.raw_mac, RAW);
  assert.notEqual(row.device_key_hash, KEY);
  assert.match(row.device_key_hash, /^[a-f0-9]{64}$/);
  assert.match(f.db.prepare('SELECT label FROM devices').get().label, /NOVATUBE 4K.*123456789ABC/);
  assert.ok(r.headers.get('cache-control').includes('no-store'));
  assert.ok(!JSON.stringify(r.body).includes(KEY));
});

test('rejouer register avec la même clé conserve la licence et son activation', async (t) => {
  const f = fixture(t);
  const first = await call(f, 'register');
  const id = license(f).id;
  activate(f, null);
  const replay = await call(f, 'register', { raw_mac: '12:34:56:78:9a:bc' });
  assert.equal(replay.status, 200);
  assert.equal(replay.body.created, false);
  assert.equal(replay.body.mac, first.body.mac);
  assert.equal(replay.body.active, true);
  assert.equal(replay.body.expires_at, null);
  assert.equal(license(f).id, id);
  assert.equal(count(f, 'devices'), 1);
  assert.equal(count(f, 'licenses'), 1);
});

test('une autre clé ne réclame pas la fiche et ne lit jamais ses sources', async (t) => {
  const f = fixture(t);
  await call(f, 'register');
  activate(f);
  const previousReads = f.calls.sources;
  const r = await call(f, 'register', { raw_mac: RAW }, { key: OTHER_KEY });
  assert.equal(r.status, 409);
  assert.equal(r.body.error, 'device_key_conflict');
  const s = await call(f, 'state', { raw_mac: RAW }, { key: OTHER_KEY });
  assert.equal(s.status, 401);
  assert.equal(f.calls.sources, previousReads);
  assert.equal(count(f, 'devices'), 1);
  assert.equal((await call(f, 'state')).body.active, true);
});

test('deux register simultanés même clé sont idempotents sans client orphelin', async (t) => {
  const f = fixture(t, { jitterMs: 3 });
  const before = count(f, 'customers');
  const results = await Promise.all([call(f, 'register'), call(f, 'register')]);
  assert.deepEqual(results.map((x) => x.status), [200, 200]);
  assert.equal(results.filter((x) => x.body.created).length, 1);
  assert.equal(count(f, 'customers'), before + 1);
  assert.equal(count(f, 'devices'), 1);
  assert.equal(count(f, 'licenses'), 1);
});

test('deux register simultanés clés différentes : un gagnant, aucun écrasement', async (t) => {
  const f = fixture(t, { jitterMs: 3 });
  const before = count(f, 'customers');
  const results = await Promise.all([
    call(f, 'register'), call(f, 'register', { raw_mac: RAW }, { key: OTHER_KEY }),
  ]);
  assert.deepEqual(results.map((x) => x.status).sort(), [200, 409]);
  assert.equal(count(f, 'customers'), before + 1);
  assert.equal(count(f, 'novatube4k_devices'), 1);
});

test('state et ack inconnus ne créent aucun appareil ou licence', async (t) => {
  const f = fixture(t);
  const before = count(f, 'customers');
  for (const action of ['state', 'ack']) {
    const r = await call(f, action, { raw_mac: RAW, source_rev: 1, applied: true });
    assert.equal(r.status, 401);
  }
  assert.equal(count(f, 'customers'), before);
  assert.equal(count(f, 'devices'), 0);
  assert.equal(count(f, 'licenses'), 0);
  assert.equal(count(f, 'novatube4k_devices'), 0);
  assert.equal(f.db.prepare('SELECT id FROM apps WHERE id=?').get(NOVATUBE4K_APP_ID), undefined);
});

test('licence d’une autre app ignorée, puis expiry et blocages toujours appliqués', async (t) => {
  const f = fixture(t);
  await call(f, 'register');
  // Simule une licence NovaTube désactivée : l'essai initial est testé à part.
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE app_id=?").run(NOVATUBE4K_APP_ID);
  const own = license(f);
  f.db.prepare(`INSERT INTO licenses
    (id,customer_id,device_id,app_id,status,plan,started_at,expires_at,created_at,updated_at)
    VALUES ('lic_other',?,?,?,'active','lifetime',?,NULL,?,?)`)
    .run(own.customer_id, own.device_id, 'app_7motion', Date.now(), Date.now(), Date.now());
  assert.equal((await call(f, 'state')).body.active, false);
  const cases = [
    ['active', Date.now() + 86_400_000, null, 1, 'active'],
    ['active', null, null, 1, 'active'],
    ['active', Date.now() - 1, null, 1, 'expired'],
    ['inactive', Date.now() + 86_400_000, null, 1, 'inactive'],
    ['active', null, 'frozen', 1, 'frozen'],
    ['active', null, 'banned', 1, 'banned'],
    ['frozen', null, null, 1, 'frozen'],
    ['banned', null, null, 1, 'banned'],
    ['active', null, null, 0, 'disabled'],
  ];
  for (const [status, expiry, block, appActive, expected] of cases) {
    f.db.prepare('UPDATE licenses SET status=?,expires_at=? WHERE app_id=?').run(status, expiry, NOVATUBE4K_APP_ID);
    f.db.prepare('UPDATE devices SET block_status=?').run(block);
    f.db.prepare('UPDATE apps SET is_active=? WHERE id=?').run(appActive, NOVATUBE4K_APP_ID);
    const before = f.calls.sources;
    const r = await call(f, 'state');
    assert.equal(r.status, 200);
    assert.equal(r.body.status, expected);
    assert.equal(r.body.active, expected === 'active');
    if (expected !== 'active') {
      assert.equal(f.calls.sources, before);
      assert.deepEqual(r.body.sources, []);
    }
  }
  f.db.prepare('DELETE FROM licenses WHERE app_id=?').run(NOVATUBE4K_APP_ID);
  f.db.prepare('UPDATE apps SET is_active=1 WHERE id=?').run(NOVATUBE4K_APP_ID);
  assert.equal((await call(f, 'state')).body.active, false);
});

test('sources déchiffrées par le handler réel seulement après activation dédiée', async (t) => {
  const f = fixture(t);
  const registered = await call(f, 'register');
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE app_id=?").run(NOVATUBE4K_APP_ID);
  const source = { type: 'xtream', label: 'Fixture', server_url: 'https://provider.invalid/prefix', username: 'fixture-user', password: 'fixture-password', origin: 'panel' };
  await publish(f, registered.body.mac, 1, [source]);
  assert.ok(f.db.prepare('SELECT sources_json FROM device_sources').get().sources_json.includes('enc1.'));
  assert.equal((await call(f, 'state')).body.sources_ok, false);
  activate(f);
  const r = await call(f, 'state');
  assert.equal(r.body.active, true);
  assert.equal(r.body.sources_ok, true);
  assert.equal(r.body.source_rev, 1);
  assert.equal(r.body.sources[0].password, 'fixture-password');
  assert.equal(r.body.sources[0].server_url, source.server_url);
  assert.equal(f.db.prepare('SELECT last_served_rev FROM novatube4k_devices').get().last_served_rev, 1);
});

test('erreur du catalogue et publication concurrente ne signifient jamais suppression', async (t) => {
  const f = fixture(t);
  const r = await call(f, 'register');
  activate(f);
  await publish(f, r.body.mac, 1, []);
  const failed = await call(f, 'state', { raw_mac: RAW }, { deps: { readSources: async () => { throw Error('fixture'); } } });
  assert.equal(failed.body.active, true);
  assert.equal(failed.body.sources_ok, false);
  const raced = await call(f, 'state', { raw_mac: RAW }, { deps: {
    readSources: async () => {
      await publish(f, r.body.mac, 2, []);
      return Response.json({ sources: [{ label: 'old' }], rev: 2 });
    },
  } });
  assert.equal(raced.body.sources_ok, false);
  assert.deepEqual(raced.body.sources, []);
  assert.equal(raced.body.source_rev, null);
  assert.equal(f.db.prepare('SELECT last_served_rev FROM novatube4k_devices').get().last_served_rev, null);
});

test('identités de source dédiées stables, uniques et jamais écrites dans le store partagé', async (t) => {
  const f = fixture(t);
  const r = await call(f, 'register');
  activate(f);
  const sources = [
    { type: 'm3u', label: 'Initial', m3u_url: 'https://list.invalid/a.m3u?token=signed', origin: 'panel' },
    { type: 'xtream', label: 'Initial', server_url: 'https://provider.invalid/prefix', username: 'u1', password: 'old', origin: 'panel' },
    { type: 'xtream', label: 'Other', server_url: 'https://provider.invalid/prefix', username: 'u2', password: 'other', origin: 'panel' },
    { type: 'm3u', id: 'valid-existing-id', m3u_url: 'https://list.invalid/existing.m3u', origin: 'self' },
  ];
  await publish(f, r.body.mac, 1, sources);
  const first = (await call(f, 'state')).body;
  assert.equal(first.sources_ok, true);
  const ids = first.sources.map((s) => s.id);
  assert.equal(new Set(ids).size, 4);
  assert.match(ids[0], /^n4k_[a-f0-9]{64}$/);
  assert.equal(ids[3], 'valid-existing-id');
  assert.notEqual(ids[1], ids[2]);
  sources[0].label = 'Renamed';
  sources[1] = { ...sources[1], label: 'Renamed', password: 'new', server_url: 'https://PROVIDER.invalid:443/prefix/' };
  await publish(f, r.body.mac, 2, sources);
  const second = (await call(f, 'state')).body;
  assert.equal(second.sources_ok, true);
  assert.deepEqual(second.sources.map((s) => s.id), ids);
  const stored = JSON.parse(f.db.prepare('SELECT sources_json FROM device_sources').get().sources_json);
  assert.equal(stored[0].id, undefined);
  assert.equal(stored[1].id, undefined);
  sources[0].m3u_url += '&new=1';
  await publish(f, r.body.mac, 3, sources);
  assert.notEqual((await call(f, 'state')).body.sources[0].id, ids[0]);
});

test('échec du lot d’enrôlement annule fiche, licence et client puis permet un retry', async (t) => {
  const f = fixture(t);
  const before = count(f, 'customers');
  f.faults.add({ match: /INSERT INTO licenses/, times: 1 });
  const failed = await call(f, 'register');
  assert.equal(failed.status, 503);
  assert.equal(count(f, 'customers'), before);
  assert.equal(count(f, 'devices'), 0);
  assert.equal(count(f, 'licenses'), 0);
  assert.equal(count(f, 'novatube4k_devices'), 0);
  assert.equal((await call(f, 'register')).status, 200);
  assert.equal(count(f, 'devices'), 1);
});

test('conflit de package refusé sans changer l’app existante', async (t) => {
  const f = fixture(t);
  f.db.prepare(`INSERT INTO apps (id,name,package_name,created_at,updated_at)
    VALUES ('app_other','Existing',?,?,?)`).run(NOVATUBE4K_PACKAGE, Date.now(), Date.now());
  const r = await call(f, 'register');
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'app_registration_conflict');
  assert.equal(count(f, 'devices'), 0);
  assert.equal(f.db.prepare("SELECT name FROM apps WHERE id='app_other'").get().name, 'Existing');
});

test('collision avec une fiche non liée ne permet pas de la réclamer', async (t) => {
  const f = fixture(t);
  const mac = await novatube4kAtlasMac(RAW);
  f.db.prepare("INSERT INTO customers(id,name,created_at,updated_at) VALUES ('existing','Existing',1,1)").run();
  f.db.prepare("INSERT INTO devices(id,customer_id,mac,label,first_seen_at,last_seen_at) VALUES ('existing','existing',?,'Old',1,1)").run(mac);
  const before = count(f, 'customers');
  const r = await call(f, 'register');
  assert.equal(r.status, 409);
  assert.equal(r.body.error, 'device_identity_conflict');
  assert.equal(count(f, 'customers'), before);
  assert.equal(count(f, 'novatube4k_devices'), 0);
  assert.equal(f.db.prepare('SELECT last_seen_at FROM devices').get().last_seen_at, 1);
});

test('ACK authentifié marque configuration et ordre source, jamais activation ou vidéo', async (t) => {
  const f = fixture(t);
  const r = await call(f, 'register');
  activate(f);
  const order = await publish(f, r.body.mac, 1, []);
  const activation = await createOrder(f.env, { mac: r.body.mac, kind: 'activate', configRev: 1 });
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true })).status, 409);
  const state = await call(f, 'state');
  assert.equal(state.body.sources_ok, true);
  const ack = await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true, app_version: 'fixture' });
  assert.equal(ack.status, 200);
  assert.equal(ack.body.result, 'config_saved');
  assert.equal(ack.body.orders_acked, 1);
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(order).state, 'applied');
  assert.equal(f.db.prepare('SELECT state FROM box_orders WHERE order_id=?').get(activation).state, 'created');
  assert.equal(f.db.prepare('SELECT state FROM source_revisions WHERE rev=1').get().state, 'acknowledged');
  const repeat = await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true });
  assert.equal(repeat.status, 200);
});

test('ACK obsolète, mauvaise clé ou licence bloquée ne marque rien appliqué', async (t) => {
  const f = fixture(t);
  const r = await call(f, 'register');
  activate(f);
  await publish(f, r.body.mac, 1, []);
  await call(f, 'state');
  await publish(f, r.body.mac, 2, []);
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true })).status, 409);
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 2, applied: true })).status, 409);
  await call(f, 'state');
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 2, applied: true }, { key: OTHER_KEY })).status, 401);
  f.db.prepare("UPDATE devices SET block_status='frozen'").run();
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 2, applied: true })).status, 403);
  assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM box_orders WHERE state='applied'").get().n, 0);
  assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM source_revisions WHERE state='acknowledged'").get().n, 0);
});

test('limiteur injecté avant les écritures, réponses refusées jamais autorisantes', async (t) => {
  const f = fixture(t);
  const r = await call(f, 'register', { raw_mac: RAW }, { deps: { rateLimitOk: async () => false } });
  assert.equal(r.status, 429);
  assert.equal(r.body.active, undefined);
  assert.ok(r.headers.get('cache-control').includes('no-store'));
  assert.equal(count(f, 'devices'), 0);
  assert.equal(f.db.prepare("SELECT name FROM sqlite_master WHERE name='novatube4k_devices'").get(), undefined);
  assert.equal((await call(f, 'register', { raw_mac: RAW }, { deps: { rateLimitOk: null } })).status, 503);
});

test('validation bornée des requêtes et route étrangère laissée au Worker', async (t) => {
  const f = fixture(t);
  assert.equal((await call(f, 'register', {}, { key: '' })).status, 401);
  assert.equal((await call(f, 'register', {}, { key: 'AB'.repeat(32) })).status, 401);
  assert.equal((await call(f, 'register', {}, { text: '{' })).status, 400);
  assert.equal((await call(f, 'register', {})).status, 400);
  assert.equal((await call(f, 'register', {}, { text: JSON.stringify({ raw_mac: RAW, extra: 'x'.repeat(5000) }) })).status, 413);
  assert.equal((await call(f, 'register', {}, { method: 'GET' })).status, 405);
  assert.equal((await call(f, 'unknown')).status, 404);
  assert.equal(await handleNovatube4k(new Request('https://fixture.test/api/status/anything'), f.env, f.deps), null);
  assert.equal(count(f, 'devices'), 0);
});

test('détection du wrapper : table absente tolérée, panne D1 jamais traitée comme ancien appareil', async (t) => {
  const f = fixture(t);
  const mac = await novatube4kAtlasMac(RAW);
  assert.equal(await isNovatube4kMac(f.env, mac), false);
  await call(f, 'register');
  assert.equal(await isNovatube4kMac(f.env, mac.toLowerCase()), true);
  f.faults.add({ match: /SELECT 1 AS found/, times: 1 });
  await assert.rejects(() => isNovatube4kMac(f.env, mac), /D1_ERROR/);
});

test('présence authentifiée au premier register puis limitée à un appel par 30 secondes', async (t) => {
  const f = fixture(t);
  const seen = [];
  f.deps.recordPresence = async (...args) => { seen.push(args); };
  const options = { headers: { 'CF-Connecting-IP': '192.0.2.10', 'CF-IPCountry': 'FR' } };
  const first = await call(f, 'register', { raw_mac: RAW }, options);
  assert.equal(seen.length, 1);
  assert.equal(seen[0][1], first.body.mac);
  assert.equal(seen[0][2], '192.0.2.10');
  assert.equal(seen[0][3], 'FR');
  assert.equal(seen[0][5], '');
  await call(f, 'state', { raw_mac: RAW }, options);
  await call(f, 'register', { raw_mac: RAW }, options);
  assert.equal(seen.length, 1);
  f.db.prepare('UPDATE novatube4k_devices SET updated_at=?').run(Date.now() - 31_000);
  await call(f, 'state', { raw_mac: RAW }, { ...options, key: OTHER_KEY });
  assert.equal(seen.length, 1);
  await call(f, 'state', { raw_mac: RAW }, options);
  assert.equal(seen.length, 2);
});

test('migration de liaison antérieure ajoute last_served_rev sans enrôler via state', async (t) => {
  const f = fixture(t);
  f.db.exec(`CREATE TABLE novatube4k_devices (
    raw_mac TEXT PRIMARY KEY, mac TEXT NOT NULL UNIQUE, device_id TEXT NOT NULL UNIQUE,
    device_key_hash TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)`);
  assert.equal((await call(f, 'state')).status, 401);
  assert.ok(f.db.prepare('PRAGMA table_info(novatube4k_devices)').all().some((x) => x.name === 'last_served_rev'));
  assert.equal(count(f, 'devices'), 0);
  assert.equal((await call(f, 'register')).status, 200);
});

test('échec de reçu de livraison ou d’ACK ne produit pas de confirmation mensongère', async (t) => {
  const f = fixture(t);
  const r = await call(f, 'register');
  activate(f);
  await publish(f, r.body.mac, 1, []);
  f.faults.add({ match: /UPDATE novatube4k_devices SET last_served_rev/, times: 1 });
  const unavailable = await call(f, 'state');
  assert.equal(unavailable.body.sources_ok, false);
  assert.equal(unavailable.body.source_rev, null);
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true })).status, 409);
  await call(f, 'state');
  f.faults.add({ match: /UPDATE source_revisions SET state/, times: 2 });
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true })).status, 503);
  assert.equal(f.db.prepare('SELECT state FROM source_revisions WHERE rev=1').get().state, 'published');
  assert.equal((await call(f, 'ack', { raw_mac: RAW, source_rev: 1, applied: true })).status, 200);
});
