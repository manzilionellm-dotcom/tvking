// Recette commerciale sur SQLite transactionnel local : aucun appareil réel,
// aucun fournisseur réseau et aucun paiement. Le temps est celui du serveur.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createD1 } from './test_support/d1_sqlite.mjs';
import { handleNovatube4k, novatube4kAtlasMac } from './novatube4k.js';
import { NOVATUBE_TRIAL_MS } from './novatube4k-trial-entitlement.js';

const APP = 'app_novatube4k', PACKAGE = 'com.manthefew';
const RAW = '00A1B2C3D4E5', KEY = '31'.repeat(32), OTHER_KEY = '57'.repeat(32);
const NOW = Date.UTC(2026, 10, 14, 16, 0, 0);

function fixture(t, options = {}) {
  const f = createD1(options);
  t.after(() => f.db.close());
  f.env = { DB: f.DB };
  f.reads = 0;
  f.deps = {
    async rateLimitOk() { return true; },
    async readSources() { f.reads++; return Response.json({ sources: [], rev: null }); },
  };
  f.call = async (action = 'register', { key = KEY, raw = RAW, body = {}, deps = {} } = {}) => {
    const response = await handleNovatube4k(new Request('https://fixture.test/api/novatube4k/' + action, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Key': key },
      body: JSON.stringify({ raw_mac: raw, ...body }),
    }), f.env, { ...f.deps, ...deps });
    return { status: response.status, body: await response.json() };
  };
  f.license = () => ({ ...f.db.prepare('SELECT * FROM licenses WHERE app_id = ?').get(APP) });
  f.anchor = () => ({ ...f.db.prepare('SELECT * FROM novatube4k_trial_entitlements WHERE raw_mac = ?').get(RAW) });
  f.count = (table) => f.db.prepare('SELECT COUNT(*) AS n FROM ' + table).get().n;
  return f;
}

async function legacy(f, { status = 'inactive', plan = 'custom', expiry = 0, block = null, active = 1 } = {}) {
  const mac = await novatube4kAtlasMac(RAW);
  f.db.exec(`CREATE TABLE novatube4k_devices (
    raw_mac TEXT PRIMARY KEY, mac TEXT NOT NULL UNIQUE, device_id TEXT NOT NULL UNIQUE,
    device_key_hash TEXT NOT NULL, last_served_rev INTEGER, created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL, FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE)`);
  f.db.prepare(`INSERT INTO apps (id,name,package_name,is_active,created_at,updated_at) VALUES (?,?,?,?,?,?)`)
    .run(APP, 'Fixture NovaTube', PACKAGE, active, NOW - 1000, NOW - 1000);
  f.db.prepare(`INSERT INTO customers (id,name,created_at,updated_at) VALUES ('customer_fixture','Fixture',?,?)`)
    .run(NOW - 1000, NOW - 1000);
  f.db.prepare(`INSERT INTO devices (id,customer_id,mac,block_status,first_seen_at,last_seen_at)
    VALUES ('device_fixture','customer_fixture',?,?,?,?)`).run(mac, block, NOW - 1000, NOW - 1000);
  f.db.prepare(`INSERT INTO licenses (id,customer_id,device_id,app_id,status,plan,started_at,expires_at,auto_renew,created_at,updated_at)
    VALUES ('license_fixture','customer_fixture','device_fixture',?,?,?,?,?,0,?,?)`)
    .run(APP, status, plan, NOW - 1000, expiry, NOW - 1000, NOW - 1000);
  f.db.prepare(`INSERT INTO novatube4k_devices
    (raw_mac,mac,device_id,device_key_hash,created_at,updated_at) VALUES (?,?,'device_fixture',?,?,?)`)
    .run(RAW, mac, createHash('sha256').update(KEY).digest('hex'), NOW - 1000, NOW - 1000);
  return mac;
}

test('premier register : dix jours exacts depuis le serveur, 999 EUR cents, aucun prélèvement ni faux checkout', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const f = fixture(t);
  const result = await f.call('register', { body: {
    now: NOW + 999999999, trial_days: 365, expires_at: NOW + 9999999999, auto_renew: true,
  } });
  assert.equal(result.status, 200);
  assert.equal(result.body.created, true);
  assert.equal(result.body.active, true);
  assert.equal(result.body.playback_allowed, true);
  assert.equal(result.body.access_kind, 'trial');
  assert.equal(result.body.plan, 'trial10');
  assert.equal(result.body.server_now, NOW);
  assert.equal(result.body.expires_at, NOW + NOVATUBE_TRIAL_MS);
  assert.deepEqual(result.body.trial, {
    duration_days: 10, status: 'active', started_at: NOW, expires_at: NOW + NOVATUBE_TRIAL_MS,
  });
  assert.deepEqual(result.body.commerce, {
    price_minor: 999, currency: 'EUR', auto_renew: false, license_duration: null,
    checkout_available: false, checkout_url: null,
  });
  assert.equal(f.license().auto_renew, 0);
  assert.equal(f.anchor().expires_at - f.anchor().started_at, 10 * 86400000);
  assert.equal(f.count('credit_ledger'), 0);
  assert.equal(f.count('payments'), 0);
  assert.equal(f.db.prepare("SELECT name FROM sqlite_master WHERE name='trial_anchors'").get(), undefined);
});

test('frontière exacte : autorisé à J10 moins 1 ms, lecture fermée à J10 sans effacement', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const f = fixture(t);
  await f.call();
  const anchor = f.anchor(), license = f.license();
  t.mock.timers.setTime(NOW + NOVATUBE_TRIAL_MS - 1);
  assert.equal((await f.call('state')).body.active, true);
  const reads = f.reads;
  t.mock.timers.setTime(NOW + NOVATUBE_TRIAL_MS);
  const expired = await f.call('state');
  assert.equal(expired.body.status, 'expired');
  assert.equal(expired.body.active, false);
  assert.equal(expired.body.playback_allowed, false);
  assert.equal(expired.body.access_kind, 'none');
  assert.equal(expired.body.trial.status, 'expired');
  assert.equal(f.reads, reads);
  assert.equal(f.count('devices'), 1);
  assert.deepEqual(f.license(), license);
  assert.deepEqual(f.anchor(), anchor);
});

test('register/state/réseau/reprise après expiration ne prolongent jamais l’ancre ni la licence', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const f = fixture(t);
  await f.call();
  const anchor = f.anchor(), license = f.license();
  t.mock.timers.setTime(NOW + 5 * 86400000);
  const network = await f.call('state', { deps: { async readSources() { throw new Error('fixture offline'); } } });
  assert.equal(network.status, 200);
  assert.equal(network.body.active, true);
  assert.equal(network.body.sources_ok, false);
  const replay = await f.call();
  assert.equal(replay.body.created, false);
  assert.equal(replay.body.expires_at, license.expires_at);
  t.mock.timers.setTime(NOW + NOVATUBE_TRIAL_MS + 5000);
  for (const action of ['register', 'state', 'register']) {
    const result = await f.call(action);
    assert.equal(result.body.status, 'expired');
    assert.equal(result.body.trial.expires_at, license.expires_at);
  }
  assert.deepEqual(f.anchor(), anchor);
  assert.deepEqual(f.license(), license);
});

test('clé concurrente et clé invalide : aucune nouvelle attribution, aucune lecture', async (t) => {
  const f = fixture(t); await f.call();
  const anchor = f.anchor(), license = f.license(), reads = f.reads;
  const conflict = await f.call('register', { key: OTHER_KEY });
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error, 'device_key_conflict');
  assert.equal((await f.call('state', { key: OTHER_KEY })).status, 401);
  assert.equal((await f.call('checkout', { key: OTHER_KEY })).status, 401);
  assert.equal(f.reads, reads);
  assert.deepEqual(f.anchor(), anchor);
  assert.deepEqual(f.license(), license);
});

test('suppression puis réenrôlement : ancre durable, aucune remise à zéro même avant J10', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const f = fixture(t); await f.call();
  const anchor = f.anchor(), firstDevice = f.license().device_id;
  f.db.prepare('DELETE FROM devices WHERE id=?').run(firstDevice);
  assert.equal(f.count('novatube4k_devices'), 0);
  assert.equal(f.count('licenses'), 0);
  assert.deepEqual(f.anchor(), anchor);
  t.mock.timers.setTime(NOW + 86400000);
  const reinstalled = await f.call('register', { key: OTHER_KEY });
  assert.equal(reinstalled.status, 200);
  assert.equal(reinstalled.body.created, true);
  assert.equal(reinstalled.body.active, false);
  assert.equal(reinstalled.body.plan, 'custom');
  assert.equal(reinstalled.body.expires_at, 0);
  assert.equal(reinstalled.body.trial.status, 'unavailable');
  assert.notEqual(f.license().device_id, firstDevice);
  assert.deepEqual(f.anchor(), anchor);
});

for (const existing of [
  { status: 'inactive', plan: 'custom', expiry: 0 },
  { status: 'active', plan: 'lifetime', expiry: null },
  { status: 'active', plan: 'yearly', expiry: NOW + 365 * 86400000 },
  { status: 'expired', plan: 'yearly', expiry: NOW - 1 },
]) test(`migration sans conversion de licence existante ${existing.status}/${existing.plan}`, async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const f = fixture(t); await legacy(f, existing);
  const before = f.license();
  const result = await f.call();
  assert.equal(result.status, 200);
  assert.equal(result.body.created, false);
  assert.equal(result.body.plan, existing.plan);
  assert.equal(result.body.expires_at, existing.expiry);
  assert.equal(result.body.trial.status, 'not_offered');
  assert.equal(result.body.active, existing.status === 'active');
  assert.equal(f.anchor().disposition, 'existing');
  assert.deepEqual(f.license(), before);
  f.db.prepare('DELETE FROM devices WHERE id=?').run(before.device_id);
  const recreated = await f.call();
  assert.equal(recreated.body.active, false);
  assert.equal(recreated.body.expires_at, 0);
});

test('app désactivée dès le premier enrôlement : aucun essai, aucune attribution différée implicite', async (t) => {
  const f = fixture(t);
  f.db.prepare(`INSERT INTO apps (id,name,package_name,is_active,created_at,updated_at) VALUES (?,?,?,0,?,?)`)
    .run(APP, 'Fixture NovaTube', PACKAGE, NOW, NOW);
  const first = await f.call();
  assert.equal(first.body.status, 'disabled');
  assert.equal(first.body.active, false);
  assert.equal(f.anchor().disposition, 'disabled');
  assert.equal(f.anchor().started_at, null);
  assert.equal(f.anchor().expires_at, null);
  f.db.prepare('UPDATE apps SET is_active=1 WHERE id=?').run(APP);
  const replay = await f.call();
  assert.equal(replay.body.status, 'inactive');
  assert.equal(replay.body.expires_at, 0);
});

for (const restricted of ['banned', 'frozen', 'disabled']) test(`blocage ${restricted} prioritaire sur l’essai, sans prolongation`, async (t) => {
  const f = fixture(t); await f.call();
  const anchor = f.anchor(), license = f.license(), reads = f.reads;
  if (restricted === 'disabled') f.db.prepare('UPDATE apps SET is_active=0 WHERE id=?').run(APP);
  else f.db.prepare('UPDATE devices SET block_status=? WHERE id=?').run(restricted, license.device_id);
  for (const action of ['state', 'register']) {
    const result = await f.call(action);
    assert.equal(result.body.status, restricted);
    assert.equal(result.body.active, false);
    assert.equal(result.body.trial.status, 'unavailable');
  }
  assert.equal(f.reads, reads);
  assert.deepEqual(f.anchor(), anchor);
  assert.deepEqual(f.license(), license);
});

test('activation payée conserve toutes ses dates et remplace seulement le droit de lecture courant', async (t) => {
  const f = fixture(t); await f.call();
  const anchor = f.anchor();
  f.db.prepare("UPDATE licenses SET plan='lifetime',status='active',expires_at=NULL,updated_at=updated_at+1 WHERE app_id=?").run(APP);
  const paid = f.license();
  for (const action of ['state', 'register']) {
    const result = await f.call(action);
    assert.equal(result.body.active, true);
    assert.equal(result.body.access_kind, 'paid');
    assert.equal(result.body.expires_at, null);
    assert.equal(result.body.trial.status, 'not_offered');
  }
  assert.deepEqual(f.license(), paid);
  assert.deepEqual(f.anchor(), anchor);
});

test('lot atomique : une panne après écriture de l’ancre ne consomme pas l’essai', async (t) => {
  const f = fixture(t);
  f.faults.add({ match: /INSERT INTO licenses/, times: 1, when: 'after' });
  assert.equal((await f.call()).status, 503);
  assert.equal(f.count('devices'), 0);
  assert.equal(f.count('licenses'), 0);
  assert.equal(f.count('novatube4k_trial_entitlements'), 0);
  const retry = await f.call();
  assert.equal(retry.body.active, true);
  assert.equal(retry.body.plan, 'trial10');
  assert.equal(f.count('novatube4k_trial_entitlements'), 1);
});

test('premiers register concurrents : une seule ancre, une licence, un seul gagnant par clé', async (t) => {
  const f = fixture(t, { jitterMs: 3 });
  const responses = await Promise.all([
    f.call(), f.call(), f.call('register', { key: OTHER_KEY }),
  ]);
  assert.equal(f.count('novatube4k_trial_entitlements'), 1);
  assert.equal(f.count('licenses'), 1);
  assert.equal(f.count('devices'), 1);
  assert.equal(responses.filter((r) => r.body.created === true).length, 1);
  assert.ok(responses.some((r) => r.status === 409));
  for (const response of responses.filter((r) => r.status === 200)) {
    assert.equal(response.body.plan, 'trial10');
    assert.equal(response.body.expires_at, f.anchor().expires_at);
  }
});

test('une identité inconnue ne reçoit aucun essai par state ou checkout', async (t) => {
  const f = fixture(t);
  for (const action of ['state', 'checkout']) assert.equal((await f.call(action)).status, 401);
  assert.equal(f.count('devices'), 0);
  assert.equal(f.count('licenses'), 0);
  assert.equal(f.count('novatube4k_trial_entitlements'), 0);
});
