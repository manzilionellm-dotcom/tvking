import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createGoldTrialHandler, DemoUnavailable, normalizeTrialMac, orderDemoKeys, verifyTrialDevice } from '../gold_trial_policy.js';
import { hashDeviceSecret } from '../device_guard.js';
import { goldTrialAdmin } from '../gold_trial_admin.js';

// Vraies contraintes et transactions SQLite, derrière la même petite API D1.
// Le fournisseur est une fixture : aucun ticket ni crédit réel utilisé.
function database() {
  const sql = new DatabaseSync(':memory:');
  sql.exec(readFileSync(new URL('../migrations/20261028_gold_trial_policy.sql', import.meta.url), 'utf8'));
  sql.exec(readFileSync(new URL('../migrations/20261028_gold_trial_runtime.sql', import.meta.url), 'utf8'));
  const db = {
    prepare(query) {
      let args = [];
      const statement = {
        bind(...values) { args = values; return statement; },
        async first() { return sql.prepare(query).get(...args) ?? null; },
        async all() { return { results: sql.prepare(query).all(...args) }; },
        async run() { return { meta: { changes: Number(sql.prepare(query).run(...args).changes) } }; },
      };
      return statement;
    },
    async batch(statements) {
      sql.exec('BEGIN');
      try { const result = []; for (const statement of statements) result.push(await statement.run()); sql.exec('COMMIT'); return result; }
      catch (error) { sql.exec('ROLLBACK'); throw error; }
    },
  };
  return { db, sql };
}

const mac = 'MK:11:22:33:44:55';
function request({ mac: device = mac, ip = '192.0.2.1', path = '/api/gold-trial', version = '1.0', androidId = 'android-fixture' } = {}) {
  return new Request(`https://worker.example${path}`, { method: 'POST',
    headers: { 'CF-Connecting-IP': ip, 'X-Device-Secret': 'fixture-device-proof' },
    body: JSON.stringify({ mac: device, android_id: androidId, app_version: version }) });
}
function fixture(overrides = {}) {
  const { db, sql } = database();
  sql.exec('UPDATE gold_trial_settings_v2 SET gold_trial_enabled=1');
  const clock = { value: Date.UTC(2026, 9, 28, 12) };
  const created = [], delivered = [];
  const adapters = {
    verifyDevice: async (req, identity) => ['android-fixture','android-second'].includes(identity.android_id) && req.headers.get('X-Device-Secret') === 'fixture-device-proof' ? 'ok' : 'device_mismatch',
    eligibility: async () => ({ trial_used: false, already_customer: false }),
    listDemoKeys: async () => [{ label: 'Manzi8', trial_priority: 0 }, { label: 'manzi10', trial_priority: 99 }],
    createDemo24h: async (key, options) => { created.push({ key, options }); return { isDemo: true, paidCreditsUsed: 0, expire: clock.value + 86_400_000, line_id: 'line-fixture' }; },
    deliverSource: async (device, result) => { delivered.push({ device, result }); return true; },
    ...overrides,
  };
  const handle = createGoldTrialHandler(adapters, { now: () => clock.value });
  const env = { DB: db, GOLD_TRIAL_POLICY_READY: 'true' };
  return { db, sql, handle, env, clock, created, delivered, adapters };
}

test('migration additive répétable, essai OFF par défaut', () => {
  const { sql } = database();
  sql.exec(readFileSync(new URL('../migrations/20261028_gold_trial_policy.sql', import.meta.url), 'utf8'));
  assert.equal(sql.prepare('SELECT gold_trial_enabled FROM gold_trial_settings_v2').get().gold_trial_enabled, 0);
});
test('MAC canonique et ordre manzi10 puis Manzi8, sans modifier les clés', () => {
  assert.equal(normalizeTrialMac(' mk-11-22-33-44-55 '), mac);
  assert.equal(normalizeTrialMac('01:23:45:67:89:AB'), '01:23:45:67:89:AB');
  assert.equal(normalizeTrialMac('invalid'), null);
  const keys = [{ label: 'Manzi8' }, { label: 'other', demo_tickets: 0 }, { label: 'manzi10' }, { label: 'disabled', enabled: 0 }, { label: 'empty', demo_tickets: '0' }];
  assert.deepEqual(orderDemoKeys(keys).map(x => x.label), ['manzi10', 'Manzi8']);
  assert.equal(keys.length, 5);
});
test('preuve réelle : MAC ↔ Android ID ↔ empreinte du secret, sans réenrôlement', async () => {
  const { db, sql } = database();
  sql.exec('CREATE TABLE devices(mac TEXT PRIMARY KEY,android_id TEXT,block_status TEXT); DROP TABLE device_secrets; CREATE TABLE device_secrets(mac TEXT PRIMARY KEY,android_id TEXT,secret_hash TEXT)');
  const identity = { mac, android_id: 'android-fixture' };
  assert.equal(await verifyTrialDevice(db, request(), identity), 'unknown_device');
  sql.prepare('INSERT INTO devices VALUES (?,?,NULL)').run(mac, identity.android_id);
  assert.equal(await verifyTrialDevice(db, request(), identity), 'device_mismatch');
  sql.prepare('INSERT INTO device_secrets VALUES (?,?,?)').run(mac, identity.android_id, await hashDeviceSecret('fixture-device-proof'));
  assert.equal(await verifyTrialDevice(db, request(), identity), 'ok');
  assert.equal(await verifyTrialDevice(db, request(), { ...identity, android_id: 'other' }), 'device_mismatch');
  const missingSecret = request(); missingSecret.headers.delete('X-Device-Secret');
  assert.equal(await verifyTrialDevice(db, missingSecret, identity), 'device_mismatch');
  sql.exec("UPDATE devices SET block_status='banned'");
  assert.equal(await verifyTrialDevice(db, request(), identity), 'device_mismatch');
});
test('nouvel appareil : uniquement démo 24 h, source et message publics', async () => {
  const f = fixture(); const response = await f.handle(request(), f.env); const body = await response.json();
  assert.equal(response.status, 201); assert.equal(body.delivered, true);
  assert.equal(body.expire, new Date(f.clock.value + 86_400_000).toISOString());
  assert.equal(f.created[0].key.label, 'manzi10');
  assert.equal(f.created[0].options.demoOnly, true); assert.equal(f.created[0].options.durationHours, 24);
  assert.equal(f.delivered.length, 1);
  assert.doesNotMatch(JSON.stringify(body), /manzi|strong|cms-8k|line-fixture|secret|password/i);
});
test('même MAC à travers les deux routes et versions : un seul essai', async () => {
  const f = fixture(); await f.handle(request(), f.env);
  f.clock.value += 90_000;
  const response = await f.handle(request({ mac: mac.toLowerCase(), path: '/api/v1/device/trial', version: 'Zuno-109' }), f.env);
  assert.equal(response.status, 409); assert.equal((await response.json()).error, 'trial_already_used'); assert.equal(f.created.length, 1);
});
test('deux clics concurrents réservent une seule MAC', async () => {
  let release; const pending = new Promise(resolve => { release = resolve; }); let calls = 0;
  const f = fixture({ createDemo24h: async () => { calls++; await pending; return { isDemo: true, paidCreditsUsed: 0, expire: Date.UTC(2026, 9, 29, 12), line_id: 'one' }; } });
  const one = f.handle(request(), f.env);
  while (calls === 0) await new Promise(resolve => setImmediate(resolve));
  const two = await f.handle(request({ ip: '192.0.2.2' }), f.env);
  assert.equal((await two.json()).error, 'in_progress'); release(); assert.equal((await one).status, 201); assert.equal(calls, 1);
});
test('clé sans ticket confirmé : bascule, jamais de création payante', async () => {
  const keys = [];
  const f = fixture({ createDemo24h: async (key, options) => {
    assert.equal(options.demoOnly, true); keys.push(key.label);
    if (key.label === 'manzi10') throw new DemoUnavailable('empty');
    return { isDemo: true, paidCreditsUsed: 0, expire: Date.UTC(2026, 9, 29, 12), line_id: 'second' };
  } });
  assert.equal((await f.handle(request(), f.env)).status, 201); assert.deepEqual(keys, ['manzi10', 'Manzi8']);
});
test('timeout ambigu : pas de bascule ni de deuxième ligne au prochain clic', async () => {
  let calls = 0;
  const f = fixture({ createDemo24h: async () => { calls++; throw new Error('https://cms-8k.net/private?api_key=secret'); } });
  const response = await f.handle(request(), f.env);
  assert.equal(response.status, 409); assert.doesNotMatch(await response.text(), /cms|secret|http/);
  assert.equal((await f.handle(request(), f.env)).status, 409); assert.equal(calls, 1);
});
test('réponse payante ou durée > 24 h : refus fermé et aucun nouveau fournisseur', async () => {
  for (const bad of [{ isDemo: false }, { paidCreditsUsed: 1 }, { expire: Date.UTC(2026, 9, 28, 13) }, { expire: Date.UTC(2026, 10, 1) }]) {
    let calls = 0; const f = fixture({ createDemo24h: async () => { calls++; return { isDemo: true, paidCreditsUsed: 0, expire: Date.UTC(2026, 9, 29, 12), line_id: 'bad', ...bad }; } });
    assert.equal((await f.handle(request(), f.env)).status, 409); assert.equal(calls, 1); assert.equal(f.delivered.length, 0);
  }
});
test('livraison en panne : essai créé conservé et pas de recréation', async () => {
  const f = fixture({ deliverSource: async () => { throw new Error('offline'); } });
  assert.equal((await (await f.handle(request(), f.env)).json()).delivered, false);
  assert.equal((await f.handle(request(), f.env)).status, 409); assert.equal(f.created.length, 1);
});
test('interrupteur OFF, plafond zéro, appareil inconnu ou incohérent : zéro appel démo', async () => {
  for (const [setup, expected] of [
    [f => f.sql.exec('UPDATE gold_trial_settings_v2 SET gold_trial_enabled=0'), 'trial_disabled'],
    [f => f.sql.exec('UPDATE gold_trial_settings_v2 SET daily_cap=0'), 'daily_cap_reached'],
    [f => f.adapters.verifyDevice = async () => 'unknown_device', 'unknown_device'],
    [f => f.adapters.verifyDevice = async () => 'device_mismatch', 'device_mismatch'],
  ]) { const f = fixture(); setup(f); assert.equal((await (await f.handle(request(), f.env)).json()).error, expected); assert.equal(f.created.length, 0); }
});
test('historique ancien et abonnement existant bloquent avant toute clé', async () => {
  for (const [field, code] of [['trial_used', 'trial_already_used'], ['already_customer', 'already_customer']]) {
    const f = fixture({ eligibility: async () => ({ trial_used: false, already_customer: false, [field]: true }) });
    assert.equal((await (await f.handle(request(), f.env)).json()).error, code); assert.equal(f.created.length, 0);
  }
});
test('historique absent ou migration manquante ne sont jamais assimilés à appareil neuf', async () => {
  const f = fixture({ eligibility: async () => ({}) });
  assert.equal((await f.handle(request(), f.env)).status, 503); assert.equal(f.created.length, 0);
  assert.throws(() => createGoldTrialHandler({}), /Missing/);
});
test('plafond partagé entre MAC, remise à zéro au jour UTC suivant', async () => {
  const f = fixture(); f.sql.exec('UPDATE gold_trial_settings_v2 SET daily_cap=1');
  assert.equal((await f.handle(request(), f.env)).status, 201);
  assert.equal((await f.handle(request({ mac: 'MK:11:22:33:44:56', androidId: 'android-second' }), f.env)).status, 429);
  f.clock.value += 86_400_000;
  assert.equal((await f.handle(request({ mac: 'MK:11:22:33:44:56', androidId: 'android-second' }), f.env)).status, 201);
});
test('5 requêtes/min/IP, partagées entre MAC et alias ; fenêtre glissante', async () => {
  const f = fixture();
  for (let n = 0; n < 5; n++) await f.handle(request(), f.env);
  assert.equal((await (await f.handle(request({ path: '/api/v1/device/trial' }), f.env)).json()).error, 'rate_limited');
  f.clock.value += 60_001;
  assert.equal((await (await f.handle(request(), f.env)).json()).error, 'trial_already_used');
});
test('pool épuisé : réessai autorisé, historique de refus préservé', async () => {
  const f = fixture({ createDemo24h: async () => { throw new DemoUnavailable(); } });
  assert.equal((await f.handle(request(), f.env)).status, 503);
  assert.equal((await f.handle(request(), f.env)).status, 503);
  assert.equal(f.sql.prepare("SELECT COUNT(*) AS n FROM gold_trial_events_v2 WHERE reason='unavailable'").get().n, 2);
});
test('panel : rôle, paramètres, révision concurrente et préparation obligatoire', async () => {
  const f = fixture(); const url = 'https://worker.example/api/v1/gold/trial-control';
  assert.equal((await goldTrialAdmin(new Request(url), f.env, { role: 'reseller' })).status, 403);
  const put = body => new Request(url, { method: 'PUT', body: JSON.stringify(body) });
  const settings = { gold_trial_enabled: true, daily_cap: 7, revision: 0 };
  assert.equal((await goldTrialAdmin(put(settings), { DB: f.db }, { role: 'admin' })).status, 409);
  assert.equal((await goldTrialAdmin(put({ ...settings, daily_cap: -1 }), f.env, { role: 'admin' })).status, 400);
  assert.equal((await goldTrialAdmin(put(settings), f.env, { role: 'admin' })).status, 200);
  assert.equal((await goldTrialAdmin(put(settings), f.env, { role: 'admin' })).status, 409);
});
test('panel : derniers essais et historique MAC avec IP, version, ligne, expiration', async () => {
  const f = fixture(); await f.handle(request(), f.env); await f.handle(request(), f.env);
  const response = await goldTrialAdmin(new Request(`https://worker.example/api/v1/gold/trial-control/history?mac=${mac}`), f.env, { role: 'admin' });
  const data = await response.json(); assert.equal(data.history.length, 4);
  assert.equal(data.history[0].reason, 'trial_already_used');
  assert.equal(data.history[0].ip, '192.0.2.1'); assert.equal(data.history[0].app_version, '1.0');
  assert.equal(data.history[1].line_id, 'line-fixture'); assert.equal(data.history[1].expire, f.clock.value + 86_400_000);
  const recent = await goldTrialAdmin(new Request('https://worker.example/api/v1/gold/trial-control'), f.env, { role: 'admin' });
  assert.equal((await recent.json()).recent.length, 1);
});

test('corps surdimensionné : lecture arrêtée et aucun appel fournisseur', async () => {
  const f = fixture(); let cancelled = false;
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(4097)); },
    cancel() { cancelled = true; },
  });
  const req = new Request('https://worker.example/api/gold-trial', { method: 'POST', body,
    duplex: 'half', headers: { 'CF-Connecting-IP': '192.0.2.1' } });
  assert.equal((await f.handle(req, f.env)).status, 400);
  assert.equal(cancelled, true); assert.equal(f.created.length, 0);
});
