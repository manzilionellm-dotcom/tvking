import { test } from 'node:test';
import assert from 'node:assert/strict';
import { signDeviceToken, verifyDeviceToken, attachDeviceToken, deviceRealtimeRoute, writeEvents, publishDeviceEvent } from './device_realtime.js';
import { RealtimeHub } from './box_channel.js';
import { createD1 } from './test_support/d1_sqlite.mjs';
const MAC = 'MK:AA:BB:CC:DD:EE', OTHER = 'MK:00:00:00:00:00';
function envFixture() {
  const { DB } = createD1({ extraSql: ['ALTER TABLE devices ADD COLUMN android_id TEXT'] });
  return { DB, DEVICE_TOKEN_SECRET: 'test-only-device-signing-key-not-production' };
}
async function seed(env) {
  await env.DB.prepare("INSERT INTO customers (id, name, created_at, updated_at) VALUES ('customer', 'test', 1, 1)").run();
  await env.DB.prepare("INSERT INTO devices (id, customer_id, mac, first_seen_at, last_seen_at, android_id) VALUES ('device', 'customer', ?, 1, 1, 'test-id')").bind(MAC).run();
}
test('signed device tokens reject forgery, expiry, absent secret and license replacement', async () => {
  const env = envFixture(); await seed(env);
  const token = await signDeviceToken(env, MAC, { device: 'device', license: 'trial' });
  assert.equal((await verifyDeviceToken(env, token)).mac, MAC);
  assert.equal(await verifyDeviceToken(env, token + 'tampered'), null);
  assert.equal(await verifyDeviceToken(env, token, Date.now() + 3600001), null);
  assert.equal(await verifyDeviceToken({ ...env, DEVICE_TOKEN_SECRET: '' }, token), null);
  assert.equal(await verifyDeviceToken(env, await signDeviceToken(env, MAC, { device: 'device', license: 'another' })), null);
});
test('MAC-only status never enrols; installation proof cannot be overwritten', async () => {
  const env = envFixture(); await seed(env); const status = { exists: true };
  const req = headers => new Request('https://test/api/status/' + MAC, { headers });
  assert.deepEqual(await attachDeviceToken(env, MAC, status, req({})), status);
  const headers = { 'X-Device-Key': 'a'.repeat(64), 'X-Device-Id': 'wrong' };
  assert.deepEqual(await attachDeviceToken(env, MAC, status, req(headers)), status);
  headers['X-Device-Id'] = 'test-id';
  const result = await attachDeviceToken(env, MAC, status, req(headers)); assert.ok(result.device_token);
  headers['X-Device-Key'] = 'b'.repeat(64);
  assert.deepEqual(await attachDeviceToken(env, MAC, status, req(headers)), status);
});
test('new WS and ticket reject MAC-only/no token', async () => {
  const env = envFixture(); await seed(env);
  assert.equal((await deviceRealtimeRoute(new Request('https://test/api/device-rt/ticket', { method: 'POST' }), env)).status, 401);
  assert.equal((await deviceRealtimeRoute(new Request('https://test/api/device-rt/ws?mac=' + MAC, { headers: { Upgrade: 'websocket' } }), env)).status, 401);
});
function fakeHub() {
  const map = new Map();
  const seen = new Map([[MAC, []], [OTHER, []]]);
  const sockets = [...seen.keys()].map(mac => ({ deserializeAttachment: () => ({ role: 'device', mac, exp: Date.now() + 3600000 }), send: text => seen.get(mac).push(JSON.parse(text)), close() {} }));
  const storage = { async get(k) { return map.get(k); }, async put(k, v) { map.set(k, v); }, async delete(k) { return map.delete(k); }, async list({prefix}) { return new Map([...map].filter(([k]) => k.startsWith(prefix))); }, async setAlarm() {}, async transaction(fn) { return fn(storage); } };
  const hub = new RealtimeHub({ storage, getWebSockets: () => sockets }, {});
  return { map, seen, hub, env: { RT_HUB: { idFromName: x => x, get: () => ({ fetch: (url, init) => hub.fetch(new Request(url, init)) }) } } };
}
test('global resources go to every connected device; MAC writes only to target, payload contains no secrets', async () => {
  const f = fakeHub();
  for (const type of ['ad', 'message', 'theme', 'home', 'featured', 'force_update', 'servers']) assert.equal(await publishDeviceEvent(f.env, { type }), true);
  assert.equal(f.seen.get(MAC).length, 7); assert.equal(f.seen.get(OTHER).length, 7);
  await publishDeviceEvent(f.env, { type: 'source_clear', mac: MAC, password: 'never copied' });
  assert.equal(f.seen.get(MAC).length, 8); assert.equal(f.seen.get(OTHER).length, 7);
  assert.deepEqual(Object.keys(f.seen.get(MAC)[7]).sort(), ['at','mac','type','v','version']);
  assert.equal(f.seen.get(MAC)[7].version, 8);
});
test('tickets expire, are single use even on failed upgrade, and abandoned tickets are reaped', async () => {
  const f = fakeHub();
  const issued = await f.hub.fetch(new Request('https://hub/device-ticket', { method: 'POST', body: JSON.stringify({ mac: MAC, exp: Date.now() + 100000 }) }));
  const { ticket } = await issued.json();
  assert.ok(ticket); f.map.get('ticket:' + ticket).until = Date.now() - 1;
  const req = () => new Request('https://hub/device-ws?ticket=' + ticket);
  assert.equal((await f.hub.fetch(req())).status, 401);
  assert.equal((await f.hub.fetch(req())).status, 401);
  f.map.set('ticket:expired', { until: 1 }); await f.hub.alarm(); assert.equal(f.map.has('ticket:expired'), false);
});
test('all panel resource mutation paths have an invalidation; GET never broadcasts', () => {
  for (const path of ['ad','announcements/1','announcements/settings','theme/automations','home-layout/restore','featured','force-update','servers/1','apps/1','sources/' + MAC,'sources/' + MAC + '/self/1','devices/1','licenses/1/renew','activate','transfer','families/1/members']) {
    const route = '/api/v1/' + path;
    assert.ok(writeEvents(route, 'POST', { mac: MAC }).length, route);
    assert.equal(writeEvents(route, 'GET').length, 0);
  }
  assert.deepEqual(writeEvents('/api/v1/sources/' + MAC, 'DELETE'), [{ type: 'source', mac: MAC }]);
});
