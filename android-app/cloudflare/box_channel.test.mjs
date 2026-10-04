// Canal panel → box. Aucun secret, aucun flux, aucun réseau.
// Exécuter : node --test android-app/cloudflare/box_channel.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  canonicalKind,
  clampTimeout,
  containsSecretKey,
  createMacMailbox,
  eventsAfter,
  normalizeMac,
  panelMaySee,
  publicEvent,
  realtimePushOff,
  waitBody,
} from './box_channel.js';

function memoryStorage() {
  const map = new Map();
  return {
    async get(key) { return map.get(key); },
    async put(key, value) { map.set(key, value); },
  };
}

const MAC = 'MK:AA:BB:CC:DD:EE';

test('MAC et noms d\'ordres : forme stricte, rien d\'autre', () => {
  assert.equal(normalizeMac(' mk:aa:bb:cc:dd:ee '), MAC);
  assert.equal(normalizeMac('MK%3AAA%3ABB%3ACC%3ADD%3AEE'), MAC);
  assert.equal(normalizeMac('AA:BB:CC:DD:EE'), '');
  assert.equal(canonicalKind('source'), 'source');
  assert.equal(canonicalKind('source_clear'), 'source_clear');
  assert.equal(canonicalKind('password'), '');
  assert.equal(canonicalKind('http://exemple.invalid/liste'), '');
});

test('interrupteur de repli coupé par défaut', () => {
  assert.equal(realtimePushOff({}), false);
  assert.equal(realtimePushOff({ REALTIME_PUSH_OFF: '0' }), false);
  assert.equal(realtimePushOff(undefined), false);
  assert.equal(realtimePushOff({ REALTIME_PUSH_OFF: '1' }), true);
});

test('le corps public n\'a ni secret ni adresse', () => {
  const body = waitBody([
    { v: 1, seq: 4, type: 'source', mac: MAC, at: 10 },
  ], false);
  assert.equal(body.timeout, false);
  assert.equal(body.fleet.length, 0);
  assert.deepEqual(body.box, [{ id: 4, kind: 'source', created_at: 10 }]);
  assert.equal(containsSecretKey(body), false);
  assert.equal(JSON.stringify(body).includes('password'), false);
  assert.equal(JSON.stringify(body).includes('m3u'), false);
  const poisoned = { type: 'source', password: 'x' };
  assert.equal(containsSecretKey(poisoned), true);
  assert.deepEqual(Object.keys(publicEvent({
    seq: 1, type: 'source', mac: MAC, at: 1, password: 'nope', m3u_url: 'nope',
  })), ['v', 'seq', 'type', 'mac', 'at']);
});

test('un push réveille l\'attente tout de suite', async () => {
  const box = createMacMailbox(memoryStorage());
  const pending = box.wait(0, 5000);
  const event = await box.push('source', MAC);
  const body = await pending;
  assert.equal(event.seq, 1);
  assert.equal(body.timeout, false);
  assert.equal(body.box[0].kind, 'source');
  assert.equal(body.box[0].id, 1);
  assert.equal(containsSecretKey(body), false);
});

test('après le curseur, le silence dure jusqu\'au délai', async () => {
  const box = createMacMailbox(memoryStorage());
  await box.push('source', MAC);
  const started = Date.now();
  const body = await box.wait(1, 200);
  assert.equal(body.timeout, true);
  assert.equal(body.box.length, 0);
  assert.ok(Date.now() - started >= 180);
  assert.ok(Date.now() - started < 2000);
});

test('deux écritures : la box en retard reçoit les deux, pas un secret', async () => {
  const box = createMacMailbox(memoryStorage());
  await box.push('source', 'mk:aa:bb:cc:dd:ee');
  await box.push('source_clear', MAC);
  const seen = await box.since(0);
  assert.deepEqual(seen.map((e) => e.type), ['source', 'source_clear']);
  const onlyNew = eventsAfter(seen, 1);
  assert.equal(onlyNew.length, 1);
  assert.equal(onlyNew[0].type, 'source_clear');
  assert.equal(await box.push('nope', MAC), null);
});

test('le délai demandé est borné', () => {
  assert.equal(clampTimeout(undefined), 20000);
  assert.equal(clampTimeout(50), 200);
  assert.equal(clampTimeout(999999), 20000);
});

test('un revendeur ne voit pas la MAC d\'un autre', () => {
  assert.equal(panelMaySee({ id: 'r1', role: 'reseller' }, 'r1'), true);
  assert.equal(panelMaySee({ id: 'r1', role: 'reseller' }, 'r2'), false);
  assert.equal(panelMaySee({ id: 'r1', role: 'reseller' }, ''), false);
  assert.equal(panelMaySee({ id: 'admin', role: 'super_admin' }, 'r2'), true);
  assert.equal(panelMaySee(null, 'r1'), false);
});
