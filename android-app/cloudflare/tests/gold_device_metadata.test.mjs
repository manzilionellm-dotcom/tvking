// Vrai point d'entrée déployable gold.fetch + SQLite locale. Aucun réseau,
// aucun client réel, aucune modification du bundle exporté de production.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';
import { createD1 } from '../test_support/d1_sqlite.mjs';
import '../prepare_gold_runtime.mjs';
const gold = (await import('../gold.js')).default;
const adminSecret = 'fixture-metadata-not-a-production-secret';
const mac = 'MK:11:22:33:44:55';
const otherMac = 'MK:AA:22:33:44:55'; // même suffixe, autre appareil

function jwt(role = 'super_admin', sub = 'fixture-admin') {
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const h = enc({ alg: 'HS256', typ: 'JWT' });
  const p = enc({ sub, role, iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 });
  return `${h}.${p}.${createHmac('sha256', adminSecret).update(`${h}.${p}`).digest('base64url')}`;
}

function fixture() {
  const f = createD1({ schema: false });
  f.db.exec(readFileSync(new URL('../production/schema.sql', import.meta.url), 'utf8'));
  f.db.exec("INSERT INTO customers(id,created_at,updated_at) VALUES ('customer',1,1)");
  f.db.exec("INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('fixture-admin','fixture@example.invalid','unused','super_admin',1,1)");
  f.db.exec("INSERT INTO resellers(id,email,password_hash,status,created_at) VALUES ('r1','r1@example.invalid','unused','active',1),('r2','r2@example.invalid','unused','active',1)");
  const active = new Map([[mac, true], [otherMac, true]]);
  const env = { DB: f.DB, ADMIN_SECRET: adminSecret, RT_HUB: {
    idFromName: value => value,
    get: id => ({ fetch: async url => {
      assert.equal(new URL(url).pathname, '/presence', 'aucun ordre ni signal externe pendant cette recette');
      return Response.json({ online: active.get(id) === true, last_seen_at: Date.now() });
    } }),
  } };
  const ctx = { waitUntil: promise => promise.catch(() => {}) };
  const call = async (path, { body, token = jwt(), method = body === undefined ? 'GET' : 'POST' } = {}) => {
    const response = await gold.fetch(new Request(`https://fixture.example${path}`, {
      method, headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.10', 'CF-IPCountry': 'SE',
        ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env, ctx);
    return { response, body: await response.json() };
  };
  return { ...f, env, active, call };
}

const report = {
  mac, model: 'NVIDIA SHIELD Android TV', manufacturer: 'NVIDIA',
  deviceKind: 'android_tv', android: '11', appVersion: '113', appBuild: 113,
  platform: 'tv', channel: 'Chaîne de recette', androidId: 'private-android-id',
  sources: [{ type: 'xtream', name: 'Fixture', server: 'https://provider.example.invalid', username: 'private-user' }],
};

test('gold.fetch : premier heartbeat matériel visible immédiatement par MAC exacte dans /online', async () => {
  const f = fixture();
  try {
    assert.equal(f.db.prepare('PRAGMA table_info(devices)').all().some(row => row.name === 'device_kind'), false);
    const result = await f.call('/api/heartbeat', { body: report, token: null });
    assert.equal(result.response.status, 200);
    const second = await f.call('/api/heartbeat', { body: { ...report, mac: otherMac, deviceKind: 'android_phone', model: 'Samsung SM-S938B', manufacturer: 'Samsung' }, token: null });
    assert.equal(second.response.status, 200);
    const online = await f.call('/api/v1/online');
    assert.equal(online.response.status, 200);
    const row = online.body.items.find(item => item.mac === mac);
    assert.deepEqual(row, {
      mac, ip: '192.0.2.10', country: 'SE', channel: 'Chaîne de recette', lastSeen: row.lastSeen,
      deviceKind: 'android_tv', deviceModel: report.model, manufacturer: 'NVIDIA', androidRelease: '11', appVersion: '113',
    });
    assert.ok(row.lastSeen > 0);
    assert.equal(online.body.items.find(item => item.mac === otherMac).deviceKind, 'android_phone');
    assert.equal(online.body.items.find(item => item.mac === otherMac).deviceModel, 'Samsung SM-S938B');
    assert.doesNotMatch(JSON.stringify(online.body), /private-user|private-android-id|provider\.example/);
    const devices = await f.call('/api/v1/devices');
    assert.equal(devices.response.status, 200);
    assert.equal(devices.body.items.find(item => item.mac === mac).device_kind, 'android_tv');
  } finally { f.db.close(); }
});

test('ancien client / type unknown / entrée malformée : ne détruit pas un matériel connu', async () => {
  const f = fixture();
  try {
    await f.call('/api/heartbeat', { body: report });
    for (const body of [{ mac }, { mac, deviceKind: 'unknown', manufacturer: '' },
      { mac, deviceKind: { type: 'android_phone' }, manufacturer: ['invalide'] },
      { mac, deviceKind: 'tv', manufacturer: '\n\t' }]) {
      assert.equal((await f.call('/api/heartbeat', { body })).response.status, 200);
    }
    const stored = f.db.prepare('SELECT device_kind,device_manufacturer FROM devices WHERE mac=?').get(mac);
    assert.equal(stored.device_kind, 'android_tv');
    assert.equal(stored.device_manufacturer, 'NVIDIA');
    await f.call('/api/heartbeat', { body: { mac, deviceKind: 'fire_tv', manufacturer: 'Amazon\u0000' } });
    assert.equal(f.db.prepare('SELECT device_kind FROM devices WHERE mac=?').get(mac).device_kind, 'fire_tv');
    assert.equal(f.db.prepare('SELECT device_manufacturer FROM devices WHERE mac=?').get(mac).device_manufacturer, 'Amazon');
  } finally { f.db.close(); }
});

test('un ancien Zuno platform=tv ne devient pas artificiellement une télévision', async () => {
  const f = fixture();
  try {
    await f.call('/api/heartbeat', { body: { mac, platform: 'tv', model: 'Samsung SM-S938B', android: '17' } });
    const row = (await f.call('/api/v1/online')).body.items[0];
    assert.equal(row.deviceKind, '');
    assert.equal(row.deviceModel, 'Samsung SM-S938B');
    assert.equal(row.androidRelease, '17');
  } finally { f.db.close(); }
});

test('authentification et périmètre revendeur conservés sur /online et /devices', async () => {
  const f = fixture();
  try {
    await f.call('/api/heartbeat', { body: report });
    await f.call('/api/heartbeat', { body: { ...report, mac: otherMac, model: 'Autre client privé' } });
    f.db.prepare("UPDATE devices SET reseller_id='r1' WHERE mac=?").run(mac);
    f.db.prepare("UPDATE devices SET reseller_id='r2' WHERE mac=?").run(otherMac);
    assert.equal((await f.call('/api/v1/online', { token: null })).response.status, 401);
    const reseller = await f.call('/api/v1/online', { token: jwt('reseller', 'r1') });
    assert.equal(reseller.response.status, 200);
    assert.deepEqual(reseller.body.items.map(item => item.mac), [mac]);
    assert.doesNotMatch(JSON.stringify(reseller.body), /Autre client privé/);
    assert.equal((await f.call(`/api/v1/online?mac=${otherMac}`, { token: jwt('reseller', 'r1') })).body.items.length, 0);
    const devices = await f.call('/api/v1/devices', { token: jwt('reseller', 'r1') });
    assert.equal(devices.response.status, 200);
    assert.deepEqual(devices.body.items.map(item => item.mac), [mac]);
  } finally { f.db.close(); }
});

test('panne de migration : présence conservée et colonnes réessayées au heartbeat suivant', async () => {
  const f = fixture();
  try {
    f.faults.add({ match: /ALTER TABLE devices ADD COLUMN device_kind/, times: 2 });
    assert.equal((await f.call('/api/heartbeat', { body: report })).response.status, 200);
    const online = await f.call('/api/v1/online');
    assert.equal(online.response.status, 200);
    assert.equal(online.body.items[0].deviceKind, '');
    assert.equal(online.body.items[0].deviceModel, report.model);
    assert.equal((await f.call('/api/heartbeat', { body: report })).response.status, 200);
    assert.equal((await f.call('/api/v1/online')).body.items[0].deviceKind, 'android_tv');
  } finally { f.db.close(); }
});

test('heartbeat refusé : aucune colonne ajoutée ni donnée matérielle écrite', async () => {
  const f = fixture();
  try {
    const denied = await f.call('/api/heartbeat', { body: { ...report, mac: 'invalid' }, token: null });
    assert.equal(denied.response.status, 400);
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM devices').get().n, 0);
    assert.equal(f.db.prepare('PRAGMA table_info(devices)').all().some(row => row.name === 'device_kind'), false);
  } finally { f.db.close(); }
});
